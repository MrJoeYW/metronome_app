package com.example.metronome_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTROL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val config = MetronomeConfig.fromMap(call.arguments as? Map<*, *>)
                    MetronomeStateStore.latestConfig = config
                    if (MetronomeStateStore.isRunning) {
                        MetronomeService.configure(applicationContext, config)
                    }
                    result.success(true)
                }

                "start" -> {
                    val config = MetronomeConfig.fromMap(call.arguments as? Map<*, *>)
                    MetronomeStateStore.latestConfig = config
                    MetronomeService.start(this, config)
                    result.success(true)
                }

                "stop" -> {
                    MetronomeService.stop(this)
                    result.success(true)
                }

                "getStatus" -> {
                    result.success(MetronomeStateStore.snapshot())
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BEAT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    BeatEventEmitter.attach(events)
                }

                override fun onCancel(arguments: Any?) {
                    BeatEventEmitter.detach()
                }
            },
        )
    }

    companion object {
        private const val CONTROL_CHANNEL = "metronome/control"
        private const val BEAT_CHANNEL = "metronome/beat_events"
    }
}
