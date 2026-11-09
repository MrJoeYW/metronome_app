package com.example.metronome_app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * 实时调音器分析器。
 *
 * 使用 AudioRecord 读取麦克风 PCM，并用 YIN 算法估算单音基频。
 * YIN 的累积均值归一化差值函数比普通自相关更不容易出现八度误判，
 * 对吉他这类富含谐波的信号也更稳定。
 *
 * 注意：这里刻意使用 [MediaRecorder.AudioSource.MIC]，不使用 UNPROCESSED。
 * 部分机型会声称支持 UNPROCESSED，但实际录到的信号增益异常或接近静音，
 * 反而让调音器看起来“没反应”。
 */
class TunerAnalyzer(
    context: Context,
    private val sink: EventChannel.EventSink,
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var running = false

    private var worker: Thread? = null
    private var audioRecord: AudioRecord? = null

    @SuppressLint("MissingPermission")
    fun start() {
        if (running) {
            return
        }
        if (!hasMicrophonePermission()) {
            emit(mapOf("status" to "permissionDenied"))
            return
        }

        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            emit(mapOf("status" to "error"))
            return
        }

        val bufferSize = maxOf(minBuffer * 2, ANALYSIS_SIZE * 2)
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize,
        )

        val recorder = audioRecord
        if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
            emit(mapOf("status" to "error"))
            audioRecord?.release()
            audioRecord = null
            return
        }

        running = true
        worker = thread(start = true, isDaemon = true, name = "TunerAnalyzer") {
            runLoop(recorder)
        }
    }

    fun stop() {
        running = false
        worker?.interrupt()
        worker = null
        audioRecord?.run {
            try {
                if (recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    stop()
                }
            } catch (_: IllegalStateException) {
            }
            release()
        }
        audioRecord = null
    }

    private fun runLoop(recorder: AudioRecord) {
        val buffer = ShortArray(ANALYSIS_SIZE)
        try {
            recorder.startRecording()
            emit(mapOf("status" to "listening"))

            while (running) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read <= 0) {
                    emit(mapOf("status" to "error"))
                    continue
                }

                val result = analyze(buffer, read)
                if (result == null) {
                    emit(mapOf("status" to "noSignal"))
                } else {
                    emit(
                        mapOf(
                            "status" to "listening",
                            "frequency" to result.frequency,
                            "clarity" to result.clarity,
                            "rms" to result.rms,
                        ),
                    )
                }

                Thread.sleep(ANALYSIS_INTERVAL_MS)
            }
        } catch (_: SecurityException) {
            emit(mapOf("status" to "permissionDenied"))
        } catch (_: Exception) {
            if (running) {
                emit(mapOf("status" to "error"))
            }
        }
    }

    /**
     * YIN 基频检测。
     *
     * 1. 去直流后计算差值函数 d(tau)
     * 2. 转成累积均值归一化差值 d'(tau)
     * 3. 取第一个低于阈值的局部极小作为周期
     * 4. 抛物线插值细化周期并换算频率
     */
    private fun analyze(samples: ShortArray, length: Int): PitchResult? {
        if (length < MIN_ANALYSIS_LENGTH) {
            return null
        }

        val values = DoubleArray(length)
        var mean = 0.0
        for (i in 0 until length) {
            mean += samples[i] / 32768.0
        }
        mean /= length

        var sumSquares = 0.0
        for (i in 0 until length) {
            val value = samples[i] / 32768.0 - mean
            values[i] = value
            sumSquares += value * value
        }

        val rms = sqrt(sumSquares / length)
        if (rms < MIN_RMS) {
            return null
        }

        val minLag = (SAMPLE_RATE / MAX_FREQUENCY).coerceAtLeast(1)
        val maxLag = minOf(length - 1, SAMPLE_RATE / MIN_FREQUENCY)
        if (maxLag <= minLag) {
            return null
        }

        // 差值函数 d(tau)。
        val difference = DoubleArray(maxLag + 1)
        for (tau in 1..maxLag) {
            var sum = 0.0
            val limit = length - tau
            for (i in 0 until limit) {
                val delta = values[i] - values[i + tau]
                sum += delta * delta
            }
            difference[tau] = sum
        }

        // 累积均值归一化差值 d'(tau)。
        val normalized = DoubleArray(maxLag + 1)
        normalized[0] = 1.0
        var runningSum = 0.0
        for (tau in 1..maxLag) {
            runningSum += difference[tau]
            normalized[tau] = if (runningSum > 1e-12) {
                difference[tau] * tau / runningSum
            } else {
                1.0
            }
        }

        // 第一个低于阈值的局部极小。
        var bestTau = -1
        for (tau in minLag..maxLag) {
            if (normalized[tau] < YIN_THRESHOLD) {
                var local = tau
                while (local + 1 <= maxLag && normalized[local + 1] < normalized[local]) {
                    local += 1
                }
                bestTau = local
                break
            }
        }

        // 没有明显低谷时退回全局最小，但要求足够可信，避免把噪声当音高。
        if (bestTau <= 0) {
            var minValue = Double.MAX_VALUE
            var minTau = -1
            for (tau in minLag..maxLag) {
                if (normalized[tau] < minValue) {
                    minValue = normalized[tau]
                    minTau = tau
                }
            }
            if (minTau <= 0 || minValue > YIN_FALLBACK_THRESHOLD) {
                return null
            }
            bestTau = minTau
        }

        var refinedTau = bestTau.toDouble()
        if (bestTau in 1 until maxLag) {
            val previous = normalized[bestTau - 1]
            val center = normalized[bestTau]
            val next = normalized[bestTau + 1]
            val denominator = 2.0 * (2.0 * center - next - previous)
            if (abs(denominator) > 1e-9) {
                refinedTau = bestTau + (next - previous) / denominator
            }
        }
        if (refinedTau <= 0.0) {
            return null
        }

        val frequency = SAMPLE_RATE / refinedTau
        if (frequency < MIN_FREQUENCY || frequency > MAX_FREQUENCY) {
            return null
        }

        return PitchResult(
            frequency = frequency,
            clarity = (1.0 - normalized[bestTau]).coerceIn(0.0, 1.0),
            rms = rms,
        )
    }

    private fun emit(event: Map<String, Any>) {
        mainHandler.post {
            sink.success(event)
        }
    }

    private fun hasMicrophonePermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        private const val SAMPLE_RATE = 44100
        private const val ANALYSIS_SIZE = 4096
        private const val ANALYSIS_INTERVAL_MS = 20L
        private const val MIN_ANALYSIS_LENGTH = 1024
        private const val MIN_FREQUENCY = 60
        private const val MAX_FREQUENCY = 1200
        private const val MIN_RMS = 0.004
        private const val YIN_THRESHOLD = 0.15
        private const val YIN_FALLBACK_THRESHOLD = 0.30
    }
}

private data class PitchResult(
    val frequency: Double,
    val clarity: Double,
    val rms: Double,
)
