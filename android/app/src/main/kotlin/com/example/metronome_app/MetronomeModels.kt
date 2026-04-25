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
const val EXTRA_SUBDIVISION_TYPE = "extra_subdivision_type"
const val EXTRA_BEAT_TYPES = "extra_beat_types"
const val EXTRA_BEAT_RHYTHM_TYPES = "extra_beat_rhythm_types"

/**
 * Flutter 与 Android 服务共享的节拍配置模型。
 *
 * beatTypes 使用字符串 token 传递：accent / secondary / light / rest。
 * 原生引擎只关心 rest 是否静音，以及 accent 是否触发强拍音色/振动。
 * beatRhythmTypes 描述每拍内部节奏型，Android 调度线程会按该列表拆分单拍。
 */
data class MetronomeConfig(
    val bpm: Int = 120,
    val beatsPerBar: Int = 4,
    val timeSignature: String = "4/4",
    val accentSound: String = "accent",
    val regularSound: String = "wood",
    val vocalMode: String = "off",
    val accentHaptics: Boolean = true,
    val subdivisionType: Int = 0,
    val beatTypes: List<String> = listOf("accent", "light", "light", "light"),
    val beatRhythmTypes: List<String> = listOf("quarter", "quarter", "quarter", "quarter"),
) {
    /** 转成 MethodChannel 可返回给 Flutter 的 Map。 */
    fun toMap(): Map<String, Any> {
        return mapOf(
            "bpm" to bpm,
            "beatsPerBar" to beatsPerBar,
            "timeSignature" to timeSignature,
            "accentSound" to accentSound,
            "regularSound" to regularSound,
            "vocalMode" to vocalMode,
            "accentHaptics" to accentHaptics,
            "subdivisionType" to subdivisionType,
            "beatTypes" to beatTypes,
            "beatRhythmTypes" to beatRhythmTypes,
        )
    }

    /** 写入 Service Intent，供前台服务 start/configure action 读取。 */
    fun writeToIntent(intent: Intent): Intent {
        return intent.apply {
            putExtra(EXTRA_BPM, bpm)
            putExtra(EXTRA_BEATS_PER_BAR, beatsPerBar)
            putExtra(EXTRA_TIME_SIGNATURE, timeSignature)
            putExtra(EXTRA_ACCENT_SOUND, accentSound)
            putExtra(EXTRA_REGULAR_SOUND, regularSound)
            putExtra(EXTRA_VOCAL_MODE, vocalMode)
            putExtra(EXTRA_ACCENT_HAPTICS, accentHaptics)
            putExtra(EXTRA_SUBDIVISION_TYPE, subdivisionType)
            putStringArrayListExtra(EXTRA_BEAT_TYPES, ArrayList(beatTypes))
            putStringArrayListExtra(EXTRA_BEAT_RHYTHM_TYPES, ArrayList(beatRhythmTypes))
        }
    }

    companion object {
        /** 从 Flutter MethodChannel 参数解析配置。 */
        fun fromMap(raw: Map<*, *>?): MetronomeConfig {
            return MetronomeConfig(
                bpm = (raw?.get("bpm") as? Number)?.toInt() ?: 120,
                beatsPerBar = (raw?.get("beatsPerBar") as? Number)?.toInt() ?: 4,
                timeSignature = raw?.get("timeSignature") as? String ?: "4/4",
                accentSound = raw?.get("accentSound") as? String ?: "accent",
                regularSound = raw?.get("regularSound") as? String ?: "wood",
                vocalMode = raw?.get("vocalMode") as? String ?: "off",
                accentHaptics = raw?.get("accentHaptics") as? Boolean ?: true,
                subdivisionType = (raw?.get("subdivisionType") as? Number)?.toInt() ?: 0,
                beatTypes = (raw?.get("beatTypes") as? List<*>)
                    ?.mapNotNull { it as? String }
                    ?: defaultBeatTypes((raw?.get("beatsPerBar") as? Number)?.toInt() ?: 4),
                beatRhythmTypes = (raw?.get("beatRhythmTypes") as? List<*>)
                    ?.mapNotNull { it as? String }
                    ?: defaultBeatRhythmTypes((raw?.get("beatsPerBar") as? Number)?.toInt() ?: 4),
            )
        }

        /** 从 Android Service Intent 解析配置。 */
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
                subdivisionType = intent.getIntExtra(EXTRA_SUBDIVISION_TYPE, 0),
                beatTypes = intent.getStringArrayListExtra(EXTRA_BEAT_TYPES)
                    ?: defaultBeatTypes(intent.getIntExtra(EXTRA_BEATS_PER_BAR, 4)),
                beatRhythmTypes = intent.getStringArrayListExtra(EXTRA_BEAT_RHYTHM_TYPES)
                    ?: defaultBeatRhythmTypes(intent.getIntExtra(EXTRA_BEATS_PER_BAR, 4)),
            )
        }

        /** 兼容旧版本配置：第一拍强拍，其余轻拍。 */
        private fun defaultBeatTypes(beatsPerBar: Int): List<String> {
            return List(beatsPerBar.coerceIn(1, 16)) { index ->
                if (index == 0) "accent" else "light"
            }
        }

        private fun defaultBeatRhythmTypes(beatsPerBar: Int): List<String> {
            return List(beatsPerBar.coerceIn(1, 16)) { "quarter" }
        }
    }
}

/** 原生层的最新状态缓存，供 getStatus 和通知文案读取。 */
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

/**
 * EventChannel 事件发射器。
 *
 * MetronomeEngine 在后台线程调度，Flutter EventSink 必须切回主线程调用。
 */
object BeatEventEmitter {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    fun attach(nextSink: EventChannel.EventSink) {
        sink = nextSink
    }

    fun detach() {
        sink = null
    }

    fun emit(
        beatIndex: Int,
        beatsPerBar: Int,
        cycleCount: Int,
        timestampNanos: Long,
        subdivisionIndex: Int,
        subdivisionSlots: Int,
        isSilent: Boolean,
    ) {
        mainHandler.post {
            sink?.success(
                mapOf(
                    "beatIndex" to beatIndex,
                    "beatsPerBar" to beatsPerBar,
                    "cycleCount" to cycleCount,
                    "timestampNanos" to timestampNanos,
                    "subdivisionIndex" to subdivisionIndex,
                    "subdivisionSlots" to subdivisionSlots,
                    "isSilent" to isSilent,
                ),
            )
        }
    }
}
