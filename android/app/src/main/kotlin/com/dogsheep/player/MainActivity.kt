package com.dogsheep.player

// audio_service 要求 MainActivity 继承 AudioServiceActivity（而非 FlutterActivity），
// 以支持从通知栏 / 耳机按键唤醒已销毁的 Activity 恢复播放。
import com.ryanheise.audioservice.AudioServiceActivity

import android.os.Bundle
import androidx.core.util.Consumer
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import androidx.window.layout.WindowLayoutInfo
import androidx.window.java.layout.WindowInfoTrackerCallbackAdapter
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Z Fold 折叠屏三态检测入口。
 *
 * 通过 Jetpack WindowManager（androidx.window）读取铰链（[FoldingFeature]）状态，
 * 并以两条通道暴露给 Flutter：
 * - MethodChannel `com.dogsheep.player/folding` —— 一次性查询当前状态
 * - EventChannel  `com.dogsheep.player/folding/events` —— 持续监听姿态变化
 *
 * 在不具备折叠硬件 / 检测不可用的设备上，两个通道分别返回 null / 空事件，
 * Flutter 侧自然回退到按宽度判断，不影响默认布局。
 */
class MainActivity : AudioServiceActivity() {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    private lateinit var tracker: WindowInfoTrackerCallbackAdapter
    private val layoutListener = Consumer<WindowLayoutInfo> { info ->
        currentInfo = info
        emitToFoldingEvents(foldingFeatureToMap(info.displayFeatures))
    }

    /** 最近一次收到的窗口布局信息，供 MethodChannel 即时查询。 */
    private var currentInfo: WindowLayoutInfo? = null

    /** EventChannel 订阅者；仅在 Flutter 侧开始监听后非空。 */
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        tracker = WindowInfoTrackerCallbackAdapter(WindowInfoTracker.getOrCreate(this))

        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return

        methodChannel = MethodChannel(messenger, "com.dogsheep.player/folding").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFoldingFeature" -> {
                        val map = foldingFeatureToMap(currentInfo?.displayFeatures.orEmpty())
                        result.success(map)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        eventChannel =
            EventChannel(messenger, "com.dogsheep.player/folding/events").apply {
                setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        // 建立监听后立即回灌一次当前状态，避免 Flutter 侧重建后错过初值。
                        emitToFoldingEvents(
                            foldingFeatureToMap(currentInfo?.displayFeatures.orEmpty())
                        )
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                })
            }
    }

    override fun onStart() {
        super.onStart()
        tracker.addWindowLayoutInfoListener(this, directExecutor, layoutListener)
    }

    override fun onStop() {
        tracker.removeWindowLayoutInfoListener(layoutListener)
        super.onStop()
    }

    private val directExecutor = java.util.concurrent.Executor { command -> command.run() }

    private fun emitToFoldingEvents(map: Map<String, Any>?) {
        val sink = eventSink ?: return
        // EventSink 不接受 null，无铰链时下发空 Map（Flutter 侧解析为非悬停）。
        runCatching { sink.success(map ?: emptyMap<String, Any>()) }
    }

    /**
     * 从 displayFeatures 中提取 [FoldingFeature]，转换为跨语言 Map。
     *
     * 返回结构：
     * ```
     * { "state": "HALF_OPENED"|"FLAT",
     *   "orientation": "HORIZONTAL"|"VERTICAL",
     *   "bounds": { "top": Int, "bottom": Int, "left": Int, "right": Int } }
     * ```
     * 设备无折叠硬件（不含 FoldingFeature）时返回 null。
     */
    private fun foldingFeatureToMap(features: List<Any?>): Map<String, Any>? {
        val feature = features.filterIsInstance<FoldingFeature>().firstOrNull()
            ?: return null
        val b = feature.bounds
        return mapOf(
            "state" to feature.state.toString(),          // HALF_OPENED / FLAT
            "orientation" to feature.orientation.toString(), // HORIZONTAL / VERTICAL
            "bounds" to mapOf(
                "top" to b.top,
                "bottom" to b.bottom,
                "left" to b.left,
                "right" to b.right,
            ),
        )
    }
}
