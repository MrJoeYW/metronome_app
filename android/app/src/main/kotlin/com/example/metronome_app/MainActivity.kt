package com.example.metronome_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 与 Android 原生节拍层的入口桥。
 *
 * MethodChannel 负责配置、启动、停止和状态查询；EventChannel 负责把原生调度线程
 * 产生的 beat 事件推回 Flutter UI。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTROL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // 只更新配置；如果服务正在跑，立即把新配置下发给前台服务。
                "configure" -> {
                    val config = MetronomeConfig.fromMap(call.arguments as? Map<*, *>)
                    MetronomeStateStore.latestConfig = config
                    if (MetronomeStateStore.isRunning) {
                        MetronomeService.configure(applicationContext, config)
                    }
                    result.success(true)
                }

                // 启动前台服务。Android 低延迟播放、WakeLock、音频焦点都在服务内完成。
                "start" -> {
                    val config = MetronomeConfig.fromMap(call.arguments as? Map<*, *>)
                    MetronomeStateStore.latestConfig = config
                    MetronomeService.start(this, config)
                    result.success(true)
                }

                // 停止前台服务并清理原生播放状态。
                "stop" -> {
                    MetronomeService.stop(this)
                    result.success(true)
                }

                // App 恢复时 Flutter 通过它拉取原生层当前运行状态。
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
                // Flutter 开始监听时保存 sink；之后 BeatEventEmitter 会复用它发事件。
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    BeatEventEmitter.attach(events)
                }

                // 页面销毁或热重载取消监听时释放 sink，避免持有无效 Flutter 端引用。
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
