package com.example.metronome_app

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

const val EXTRA_BPM = "extra_bpm"
const val EXTRA_BEATS_PER_BAR = "extra_beats_per_bar"
const val EXTRA_TIME_SIGNATURE = "extra_time_signature"
const val EXTRA_ACCENT_SOUND = "extra_accent_sound"
const val EXTRA_REGULAR_SOUND = "extra_regular_sound"
const val EXTRA_VOCAL_MODE = "extra_vocal_mode"
const val EXTRA_ACCENT_HAPTICS = "extra_accent_haptics"

data class MetronomeConfig(
    val bpm: Int = 120,
    val beatsPerBar: Int = 4,
    val timeSignature: String = "4/4",
    val accentSound: String = "accent",
    val regularSound: String = "wood",
    val vocalMode: String = "off",
    val accentHaptics: Boolean = true,
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "bpm" to bpm,
            "beatsPerBar" to beatsPerBar,
            "timeSignature" to timeSignature,
            "accentSound" to accentSound,
            "regularSound" to regularSound,
            "vocalMode" to vocalMode,
            "accentHaptics" to accentHaptics,
        )
    }

    fun writeToIntent(intent: Intent): Intent {
        return intent.apply {
            putExtra(EXTRA_BPM, bpm)
            putExtra(EXTRA_BEATS_PER_BAR, beatsPerBar)
            putExtra(EXTRA_TIME_SIGNATURE, timeSignature)
            putExtra(EXTRA_ACCENT_SOUND, accentSound)
            putExtra(EXTRA_REGULAR_SOUND, regularSound)
            putExtra(EXTRA_VOCAL_MODE, vocalMode)
            putExtra(EXTRA_ACCENT_HAPTICS, accentHaptics)
        }
    }

    companion object {
        fun fromMap(raw: Map<*, *>?): MetronomeConfig {
            return MetronomeConfig(
                bpm = (raw?.get("bpm") as? Number)?.toInt() ?: 120,
                beatsPerBar = (raw?.get("beatsPerBar") as? Number)?.toInt() ?: 4,
                timeSignature = raw?.get("timeSignature") as? String ?: "4/4",
                accentSound = raw?.get("accentSound") as? String ?: "accent",
                regularSound = raw?.get("regularSound") as? String ?: "wood",
                vocalMode = raw?.get("vocalMode") as? String ?: "off",
                accentHaptics = raw?.get("accentHaptics") as? Boolean ?: true,
            )
        }

        fun fromIntent(intent: Intent?): MetronomeConfig {
            if (intent == null) {
                return MetronomeConfig()
            }

            return MetronomeConfig(
                bpm = intent.getIntExtra(EXTRA_BPM, 120),
                beatsPerBar = intent.getIntExtra(EXTRA_BEATS_PER_BAR, 4),
                timeSignature = intent.getStringExtra(EXTRA_TIME_SIGNATURE) ?: "4/4",
                accentSound = intent.getStringExtra(EXTRA_ACCENT_SOUND) ?: "accent",
                regularSound = intent.getStringExtra(EXTRA_REGULAR_SOUND) ?: "wood",
                vocalMode = intent.getStringExtra(EXTRA_VOCAL_MODE) ?: "off",
                accentHaptics = intent.getBooleanExtra(EXTRA_ACCENT_HAPTICS, true),
            )
        }
    }
}

object MetronomeStateStore {
    @Volatile
    var latestConfig: MetronomeConfig = MetronomeConfig()

    @Volatile
    var isRunning: Boolean = false

    @Volatile
    var currentBeat: Int = 0

    @Volatile
    var cycleCount: Int = 0

    fun snapshot(): Map<String, Any> {
        return mapOf(
            "isRunning" to isRunning,
            "currentBeat" to currentBeat,
            "cycleCount" to cycleCount,
            "config" to latestConfig.toMap(),
        )
    }
}

object BeatEventEmitter {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    fun attach(nextSink: EventChannel.EventSink) {
        sink = nextSink
    }

    fun detach() {
        sink = null
    }

    fun emit(beatIndex: Int, beatsPerBar: Int, cycleCount: Int, timestampNanos: Long) {
        mainHandler.post {
            sink?.success(
                mapOf(
                    "beatIndex" to beatIndex,
                    "beatsPerBar" to beatsPerBar,
                    "cycleCount" to cycleCount,
                    "timestampNanos" to timestampNanos,
                ),
            )
        }
    }
}
