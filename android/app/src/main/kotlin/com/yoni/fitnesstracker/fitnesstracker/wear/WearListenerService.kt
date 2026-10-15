package com.yoni.fitnesstracker.fitnesstracker.wear

import android.util.Log
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

/**
 * Ontvangt Data Layer-berichten van het horloge, ook als de Flutter-UI niet draait.
 * Een `ping` wordt hier native beantwoord met een `pong` (zodat de koppeling testbaar is
 * zonder dat Dart actief hoeft te zijn) en daarnaast aan Dart doorgegeven.
 */
class WearListenerService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        val path = event.path
        if (!path.startsWith(WearBridge.PREFIX)) return
        if (path == WearBridge.PATH_PING) replyPong(event)
        WearBridge.emit("message", path, event.sourceNodeId, event.data)
    }

    override fun onDataChanged(buffer: DataEventBuffer) {
        for (event in buffer) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            val path = item.uri.path ?: continue
            if (!path.startsWith(WearBridge.PREFIX)) continue
            // Gegevens kopiëren: de buffer wordt na deze callback vrijgegeven.
            WearBridge.emit("data", path, item.uri.host ?: "", item.data ?: ByteArray(0))
        }
    }

    private fun replyPong(event: MessageEvent) {
        val ping = try {
            JSONObject(String(event.data, Charsets.UTF_8))
        } catch (e: Exception) {
            JSONObject()
        }
        val pong = JSONObject()
            .put("v", 1)
            .put("id", ping.opt("id") ?: JSONObject.NULL)
            .put("ts", System.currentTimeMillis())
            .put("echoTs", ping.opt("ts") ?: JSONObject.NULL)
        Wearable.getMessageClient(this)
            .sendMessage(event.sourceNodeId, WearBridge.PATH_PONG, pong.toString().toByteArray(Charsets.UTF_8))
            .addOnFailureListener { Log.w("WearListener", "pong failed", it) }
    }
}
