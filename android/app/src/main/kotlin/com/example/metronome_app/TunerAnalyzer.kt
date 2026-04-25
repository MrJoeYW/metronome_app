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
 * 简单实时调音器分析器。
 *
 * 使用 AudioRecord 读取麦克风 PCM，并用归一化自相关估算单音基频。
 * 目标是先提供真实输入与稳定 UI 状态流转，后续可替换为更强的 YIN/MPM 算法。
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

    private fun analyze(samples: ShortArray, length: Int): PitchResult? {
        val values = DoubleArray(length)
        var sumSquares = 0.0
        for (i in 0 until length) {
            val value = samples[i] / 32768.0
            values[i] = value
            sumSquares += value * value
        }

        val rms = sqrt(sumSquares / length)
        if (rms < MIN_RMS) {
            return null
        }

        val minLag = SAMPLE_RATE / MAX_FREQUENCY
        val maxLag = SAMPLE_RATE / MIN_FREQUENCY
        var bestLag = -1
        var bestCorrelation = 0.0

        for (lag in minLag..maxLag) {
            var correlation = 0.0
            var energyA = 0.0
            var energyB = 0.0
            val limit = length - lag
            for (i in 0 until limit) {
                val a = values[i]
                val b = values[i + lag]
                correlation += a * b
                energyA += a * a
                energyB += b * b
            }

            val denominator = sqrt(energyA * energyB)
            if (denominator <= 0.0) {
                continue
            }

            val normalized = correlation / denominator
            if (normalized > bestCorrelation) {
                bestCorrelation = normalized
                bestLag = lag
            }
        }

        if (bestLag <= 0 || bestCorrelation < MIN_CLARITY) {
            return null
        }

        val refinedLag = refineLag(values, length, bestLag)
        val frequency = SAMPLE_RATE / refinedLag
        if (frequency < MIN_FREQUENCY || frequency > MAX_FREQUENCY) {
            return null
        }

        return PitchResult(
            frequency = frequency,
            clarity = bestCorrelation,
            rms = rms,
        )
    }

    private fun refineLag(values: DoubleArray, length: Int, lag: Int): Double {
        val previous = correlationAt(values, length, lag - 1)
        val center = correlationAt(values, length, lag)
        val next = correlationAt(values, length, lag + 1)
        val denominator = previous - 2 * center + next
        if (abs(denominator) < 1e-9) {
            return lag.toDouble()
        }
        return lag + 0.5 * (previous - next) / denominator
    }

    private fun correlationAt(values: DoubleArray, length: Int, lag: Int): Double {
        if (lag <= 0 || lag >= length) {
            return 0.0
        }
        var correlation = 0.0
        val limit = length - lag
        for (i in 0 until limit) {
            correlation += values[i] * values[i + lag]
        }
        return correlation
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
        private const val ANALYSIS_INTERVAL_MS = 70L
        private const val MIN_FREQUENCY = 60
        private const val MAX_FREQUENCY = 1200
        private const val MIN_RMS = 0.012
        private const val MIN_CLARITY = 0.62
    }
}

private data class PitchResult(
    val frequency: Double,
    val clarity: Double,
    val rms: Double,
)
