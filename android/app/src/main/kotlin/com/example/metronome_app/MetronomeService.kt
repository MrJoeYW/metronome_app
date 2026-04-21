package com.example.metronome_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale

class MetronomeService : Service(), AudioManager.OnAudioFocusChangeListener {
    private lateinit var engine: MetronomeEngine
    private lateinit var audioManager: AudioManager
    private lateinit var wakeLock: PowerManager.WakeLock
    private var audioFocusRequest: AudioFocusRequest? = null
    private var shouldResumeOnFocusGain = false
    private var notificationManager: NotificationManager? = null
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false
    private var currentVoiceMode = "off"

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:metronome-service",
        )

        engine = MetronomeEngine(
            context = applicationContext,
            onBeat = { beatIndex, beatsPerBar, cycleCount, timestampNanos, _ ->
                BeatEventEmitter.emit(beatIndex, beatsPerBar, cycleCount, timestampNanos)
            },
            onAccent = { triggerAccentHaptic() },
            onVoice = { beatIndex, config -> speakBeat(beatIndex, config) },
        )

        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startPlayback(MetronomeConfig.fromIntent(intent))
            ACTION_CONFIGURE -> applyConfiguration(MetronomeConfig.fromIntent(intent))
            ACTION_STOP -> stopPlayback(stopService = true)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        abandonAudioFocus()
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        engine.release()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder {
        return Binder()
    }

    override fun onAudioFocusChange(focusChange: Int) {
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                if (engine.isRunning()) {
                    shouldResumeOnFocusGain = true
                    engine.stop()
                    updateNotification("Paused by audio focus")
                }
            }

            AudioManager.AUDIOFOCUS_GAIN -> {
                if (shouldResumeOnFocusGain) {
                    shouldResumeOnFocusGain = false
                    engine.start()
                    MetronomeStateStore.isRunning = true
                    updateNotification("Foreground service is running")
                }
            }

            AudioManager.AUDIOFOCUS_LOSS -> {
                shouldResumeOnFocusGain = false
                stopPlayback(stopService = true)
            }
        }
    }

    private fun startPlayback(config: MetronomeConfig) {
        MetronomeStateStore.latestConfig = config
        startForeground(NOTIFICATION_ID, buildNotification(config, "Starting foreground service"))

        if (!requestAudioFocus()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        if (!wakeLock.isHeld) {
            wakeLock.acquire(WAKE_LOCK_TIMEOUT_MS)
        }

        prepareVoice(config.vocalMode)
        engine.updateConfig(config)
        engine.start()
        MetronomeStateStore.isRunning = true
        updateNotification("Foreground service is running")
    }

    private fun applyConfiguration(config: MetronomeConfig) {
        MetronomeStateStore.latestConfig = config
        engine.updateConfig(config)
        prepareVoice(config.vocalMode)
        if (MetronomeStateStore.isRunning) {
            updateNotification("Foreground service is running")
        }
    }

    private fun stopPlayback(stopService: Boolean) {
        shouldResumeOnFocusGain = false
        engine.stop()
        MetronomeStateStore.isRunning = false
        MetronomeStateStore.currentBeat = 0
        abandonAudioFocus()
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        textToSpeech?.stop()
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (stopService) {
            stopSelf()
        }
    }

    private fun requestAudioFocus(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request =
                audioFocusRequest
                    ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                        .setOnAudioFocusChangeListener(this)
                        .build()
                        .also { audioFocusRequest = it }
            audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                this,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let(audioManager::abandonAudioFocusRequest)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(this)
        }
    }

    private fun triggerAccentHaptic() {
        if (!MetronomeStateStore.latestConfig.accentHaptics) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager =
                getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            val vibrator = vibratorManager.defaultVibrator
            vibrator.vibrate(VibrationEffect.createOneShot(14, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(14, VibrationEffect.DEFAULT_AMPLITUDE),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(14)
            }
        }
    }

    private fun prepareVoice(mode: String) {
        currentVoiceMode = mode
        if (mode == "off") {
            textToSpeech?.stop()
            return
        }

        if (textToSpeech == null) {
            textToSpeech =
                TextToSpeech(applicationContext) { status ->
                    ttsReady = status == TextToSpeech.SUCCESS
                    if (ttsReady) {
                        configureVoiceLanguage(currentVoiceMode)
                    }
                }
        } else if (ttsReady) {
            configureVoiceLanguage(mode)
        }
    }

    private fun speakBeat(beatIndex: Int, config: MetronomeConfig) {
        if (config.vocalMode == "off") {
            return
        }

        if (config.vocalMode != currentVoiceMode) {
            prepareVoice(config.vocalMode)
        }
        if (!ttsReady) {
            return
        }

        val text =
            when (config.vocalMode) {
                "english" -> ENGLISH_COUNTS[beatIndex.coerceIn(0, ENGLISH_COUNTS.lastIndex)]
                "chinese" -> CHINESE_COUNTS[beatIndex.coerceIn(0, CHINESE_COUNTS.lastIndex)]
                else -> return
            }

        textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            "beat-${beatIndex}-${SystemClock.elapsedRealtime()}",
        )
    }

    private fun configureVoiceLanguage(mode: String) {
        val locale =
            when (mode) {
                "english" -> Locale.US
                "chinese" -> Locale.SIMPLIFIED_CHINESE
                else -> return
            }
        textToSpeech?.setLanguage(locale)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Metronome Playback",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps the metronome responsive while the screen is off."
            }
        notificationManager?.createNotificationChannel(channel)
    }

    private fun updateNotification(status: String) {
        notificationManager?.notify(
            NOTIFICATION_ID,
            buildNotification(MetronomeStateStore.latestConfig, status),
        )
    }

    private fun buildNotification(config: MetronomeConfig, status: String): Notification {
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Pulse Grid")
            .setContentText("${config.bpm} BPM | ${config.timeSignature} | $status")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Accent ${config.accentSound} / Regular ${config.regularSound} | Vocal ${config.vocalMode}",
                ),
            )
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "metronome_playback"
        private const val NOTIFICATION_ID = 4107
        private const val WAKE_LOCK_TIMEOUT_MS = 8 * 60 * 60 * 1000L

        const val ACTION_START = "com.example.metronome_app.action.START"
        const val ACTION_CONFIGURE = "com.example.metronome_app.action.CONFIGURE"
        const val ACTION_STOP = "com.example.metronome_app.action.STOP"

        private val ENGLISH_COUNTS = listOf("one", "two", "three", "four", "five", "six")
        private val CHINESE_COUNTS =
            listOf("\u4e00", "\u4e8c", "\u4e09", "\u56db", "\u4e94", "\u516d")

        fun start(context: Context, config: MetronomeConfig) {
            val intent =
                Intent(context, MetronomeService::class.java).apply {
                    action = ACTION_START
                }
            config.writeToIntent(intent)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }

        fun configure(context: Context, config: MetronomeConfig) {
            val intent =
                Intent(context, MetronomeService::class.java).apply {
                    action = ACTION_CONFIGURE
                }
            config.writeToIntent(intent)
            context.startService(intent)
        }

        fun stop(context: Context) {
            val intent =
                Intent(context, MetronomeService::class.java).apply {
                    action = ACTION_STOP
                }
            context.startService(intent)
        }
    }
}
