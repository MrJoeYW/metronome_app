package com.example.metronome_app

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.locks.LockSupport
import kotlin.concurrent.thread
import kotlin.math.roundToLong

/**
 * 低延迟节拍调度核心。
 *
 * SoundPool 负责播放短促 wav，后台线程按 elapsedRealtimeNanos 调度节拍。
 * Flutter 传来的 beatTypes 会在这里参与播放判断，Rest 拍会完整跳过音频、振动和 TTS。
 * beatRhythmTypes 会覆盖单拍内部发声密度，例如两个八分音符响两下，三连音均分响三下。
 */
class MetronomeEngine(
    context: Context,
    private val onBeat: (Int, Int, Int, Long, MetronomeConfig, Int, Int, Boolean) -> Unit,
    private val onAccent: () -> Unit,
    private val onVoice: (Int, MetronomeConfig) -> Unit,
) {
    private val appContext = context.applicationContext
    private val configRef = AtomicReference(MetronomeConfig())
    private val running = AtomicBoolean(false)
    private val loadedLatch = CountDownLatch(SOUND_RESOURCES.size)
    private val soundIds = ConcurrentHashMap<String, Int>()
    private val soundPool: SoundPool =
        SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()

    @Volatile
    private var schedulerThread: Thread? = null

    init {
        // SoundPool 资源异步加载；调度线程启动时最多等待一小段时间。
        soundPool.setOnLoadCompleteListener { _, _, status ->
            if (status == 0) {
                loadedLatch.countDown()
            }
        }

        for ((token, resId) in SOUND_RESOURCES) {
            soundIds[token] = soundPool.load(appContext, resId, 1)
        }
    }

    fun updateConfig(config: MetronomeConfig) {
        // AtomicReference 让 UI 线程更新配置时，调度线程能在下一 tick 读到最新快照。
        configRef.set(config)
        MetronomeStateStore.latestConfig = config
    }

    fun isRunning(): Boolean {
        return running.get()
    }

    fun start() {
        // compareAndSet 防止重复 Start 创建多个调度线程。
        if (!running.compareAndSet(false, true)) {
            return
        }

        schedulerThread = thread(
            start = true,
            isDaemon = true,
            name = "MetronomeScheduler",
        ) {
            runLoop()
        }
    }

    fun stop() {
        running.set(false)
        schedulerThread?.interrupt()
        schedulerThread = null
        MetronomeStateStore.isRunning = false
    }

    fun release() {
        stop()
        soundPool.release()
    }

    private fun runLoop() {
        loadedLatch.await(1500, TimeUnit.MILLISECONDS)

        var beatIndex = 0
        var cycleCount = 0
        var subdivisionIndex = 0
        var nextTickNanos = SystemClock.elapsedRealtimeNanos() + WARMUP_NANOS

        while (running.get()) {
            val config = configRef.get()
            if (beatIndex >= config.beatsPerBar) {
                beatIndex = 0
            }
            val pattern = activeSubdivisionPattern(config, beatIndex)
            if (subdivisionIndex >= pattern.mask.size) {
                subdivisionIndex = 0
            }

            waitPrecisely(nextTickNanos)
            if (!running.get()) {
                break
            }

            val beatType = beatTypeFor(config, beatIndex)
            val isRestBeat = beatType == "rest"
            // Rest 是整拍静音：主拍、细分、强拍振动和 TTS 都不触发。
            val shouldSound = pattern.mask[subdivisionIndex] && !isRestBeat
            if (shouldSound) {
                playTick(config, beatType, subdivisionIndex)
                if (subdivisionIndex == 0 && beatType == "accent" && config.accentHaptics) {
                    onAccent()
                }
                if (subdivisionIndex == 0 && config.vocalMode != "off") {
                    onVoice(beatIndex, config)
                }
            }

            MetronomeStateStore.isRunning = true
            MetronomeStateStore.currentBeat = beatIndex
            MetronomeStateStore.cycleCount = cycleCount
            onBeat(
                beatIndex,
                config.beatsPerBar,
                cycleCount,
                nextTickNanos,
                config,
                subdivisionIndex,
                pattern.mask.size,
                !shouldSound,
            )

            subdivisionIndex += 1
            if (subdivisionIndex >= pattern.mask.size) {
                subdivisionIndex = 0
                beatIndex += 1
                if (beatIndex >= config.beatsPerBar) {
                    beatIndex = 0
                    cycleCount += 1
                }
            }

            val intervalNanos =
                (SECONDS_TO_NANOS_PER_MINUTE / (config.bpm.toDouble() * pattern.mask.size))
                    .roundToLong()
                    .coerceAtLeast(MIN_INTERVAL_NANOS)
            nextTickNanos += intervalNanos

            val drift = SystemClock.elapsedRealtimeNanos() - nextTickNanos
            // 如果系统调度出现大漂移，重新锚定下一 tick，避免越追越偏。
            if (drift > intervalNanos) {
                nextTickNanos = SystemClock.elapsedRealtimeNanos() + intervalNanos
            }
        }
    }

    private fun waitPrecisely(targetNanos: Long) {
        // 远离目标时 park 让出 CPU，临近目标时短暂自旋，降低点击音起点抖动。
        while (running.get()) {
            val remaining = targetNanos - SystemClock.elapsedRealtimeNanos()
            if (remaining > 2_000_000L) {
                LockSupport.parkNanos(remaining - 1_000_000L)
                continue
            }
            if (remaining > 250_000L) {
                LockSupport.parkNanos(remaining / 2)
                continue
            }
            if (remaining > 0L) {
                continue
            }
            return
        }
    }

    private fun playTick(config: MetronomeConfig, beatType: String, subdivisionIndex: Int) {
        // 非 0 细分使用较轻的子拍音色；主拍按 Accent/Regular 选择音源。
        if (subdivisionIndex != 0) {
            playSubTick()
            return
        }

        val token = if (beatType == "accent") config.accentSound else config.regularSound
        val soundId = soundIds[token] ?: soundIds["accent"] ?: return
        soundPool.play(soundId, 1f, 1f, 1, 0, 1f)
    }

    private fun beatTypeFor(config: MetronomeConfig, beatIndex: Int): String {
        // 兼容旧配置：没有 beatTypes 时第一拍强拍，其余轻拍。
        return config.beatTypes.getOrNull(beatIndex)
            ?: if (beatIndex == 0) "accent" else "light"
    }

    private fun activeSubdivisionPattern(config: MetronomeConfig, beatIndex: Int): SubdivisionPattern {
        val rhythmPattern = rhythmPattern(rhythmTypeFor(config, beatIndex))
        return rhythmPattern ?: subdivisionPattern(config.subdivisionType)
    }

    private fun rhythmTypeFor(config: MetronomeConfig, beatIndex: Int): String {
        return config.beatRhythmTypes.getOrNull(beatIndex) ?: "quarter"
    }

    private fun playSubTick() {
        val soundId = soundIds["electronic"] ?: soundIds["mechanical"] ?: return
        soundPool.play(soundId, 0.56f, 0.56f, 0, 0, 1.35f)
    }

    companion object {
        private const val WARMUP_NANOS = 80_000_000L
        private const val MIN_INTERVAL_NANOS = 1_000_000L
        private const val SECONDS_TO_NANOS_PER_MINUTE = 60_000_000_000.0

        private val SOUND_RESOURCES = mapOf(
            "accent" to R.raw.click_accent,
            "mechanical" to R.raw.click_mechanical,
            "electronic" to R.raw.click_electronic,
            "wood" to R.raw.click_wood,
        )

        private fun subdivisionPattern(type: Int): SubdivisionPattern {
            // mask 中 true 表示该细分位置发声，false 表示细分内静音。
            return when (type) {
                1 -> SubdivisionPattern(booleanArrayOf(true, true))
                2 -> SubdivisionPattern(booleanArrayOf(true, true, true, true))
                3 -> SubdivisionPattern(booleanArrayOf(true, true, true))
                4 -> SubdivisionPattern(booleanArrayOf(true, false, true, true))
                5 -> SubdivisionPattern(booleanArrayOf(true, true, true, false))
                6 -> SubdivisionPattern(booleanArrayOf(true, false, false, true))
                else -> SubdivisionPattern(booleanArrayOf(true))
            }
        }

        private fun rhythmPattern(type: String): SubdivisionPattern? {
            // quarter 继续使用全局 subdivisionType，避免破坏旧的细分控制。
            return when (type) {
                "eighth", "eighth_pair" -> SubdivisionPattern(booleanArrayOf(true, true))
                "eighth_rest" -> SubdivisionPattern(booleanArrayOf(true, false))
                "rest_eighth" -> SubdivisionPattern(booleanArrayOf(false, true))
                "eighth_triplet", "sixteenth_triplet" -> SubdivisionPattern(booleanArrayOf(true, true, true))
                "triplet_rest_first" -> SubdivisionPattern(booleanArrayOf(false, true, true))
                "triplet_rest_middle" -> SubdivisionPattern(booleanArrayOf(true, false, true))
                "triplet_rest_last" -> SubdivisionPattern(booleanArrayOf(true, true, false))
                "sixteenth", "thirty_second", "sixteenth_four" ->
                    SubdivisionPattern(booleanArrayOf(true, true, true, true))
                "dotted_eighth", "dotted", "front_eight_back_sixteen", "dotted_eighth_sixteenth" ->
                    SubdivisionPattern(booleanArrayOf(true, false, false, true))
                "front_sixteen_back_eight", "sixteenth_dotted_eighth" ->
                    SubdivisionPattern(booleanArrayOf(true, true, false, false))
                else -> null
            }
        }
    }
}

private data class SubdivisionPattern(val mask: BooleanArray)
