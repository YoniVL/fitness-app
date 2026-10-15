package com.yoni.fitnesstracker.fitnesstracker.wear

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter-kant van de horlogebrug.
 *
 * MethodChannel `cadans/wear`:
 *  - `send` {path: String, data: ByteArray} -> {nodes, sent, error?}
 *  - `nodes` -> [{id, name, nearby}]
 * EventChannel `cadans/wear/events`: {kind: "message"|"data", path, nodeId, data: ByteArray}
 */
class WearBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var context: Context? = null
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "cadans/wear").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "cadans/wear/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        WearBridge.detach()
        methods = null
        events = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("no_context", "Plugin niet gekoppeld", null)
            return
        }
        when (call.method) {
            "send" -> {
                val path = call.argument<String>("path")
                val data = call.argument<ByteArray>("data") ?: ByteArray(0)
                if (path == null || !path.startsWith(WearBridge.PREFIX)) {
                    result.error("bad_path", "Pad moet beginnen met ${WearBridge.PREFIX}", null)
                    return
                }
                WearBridge.send(ctx, path, data) { nodes, sent, error ->
                    result.success(mapOf("nodes" to nodes, "sent" to sent, "error" to error))
                }
            }
            "nodes" -> WearBridge.nodes(ctx) { list ->
                if (list == null) result.error("nodes_failed", "Kon verbonden horloges niet ophalen", null)
                else result.success(list)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) = WearBridge.attach(sink)

    override fun onCancel(arguments: Any?) = WearBridge.detach()
}
