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

class MetronomeEngine(
    context: Context,
    private val onBeat: (Int, Int, Int, Long, MetronomeConfig) -> Unit,
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
        configRef.set(config)
        MetronomeStateStore.latestConfig = config
    }

    fun isRunning(): Boolean {
        return running.get()
    }

    fun start() {
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
        var nextTickNanos = SystemClock.elapsedRealtimeNanos() + WARMUP_NANOS

        while (running.get()) {
            val config = configRef.get()
            if (beatIndex >= config.beatsPerBar) {
                beatIndex = 0
            }

            waitPrecisely(nextTickNanos)
            if (!running.get()) {
                break
            }

            playBeat(config, beatIndex)
            if (beatIndex == 0 && config.accentHaptics) {
                onAccent()
            }
            if (config.vocalMode != "off") {
                onVoice(beatIndex, config)
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
            )

            beatIndex += 1
            if (beatIndex >= config.beatsPerBar) {
                beatIndex = 0
                cycleCount += 1
            }

            val intervalNanos =
                (SECONDS_TO_NANOS_PER_MINUTE / config.bpm.toDouble()).roundToLong()
                    .coerceAtLeast(MIN_INTERVAL_NANOS)
            nextTickNanos += intervalNanos

            val drift = SystemClock.elapsedRealtimeNanos() - nextTickNanos
            if (drift > intervalNanos) {
                nextTickNanos = SystemClock.elapsedRealtimeNanos() + intervalNanos
            }
        }
    }

    private fun waitPrecisely(targetNanos: Long) {
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

    private fun playBeat(config: MetronomeConfig, beatIndex: Int) {
        val token = if (beatIndex == 0) config.accentSound else config.regularSound
        val soundId = soundIds[token] ?: soundIds["accent"] ?: return
        soundPool.play(soundId, 1f, 1f, 1, 0, 1f)
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
    }
}
