package com.yoni.fitnesstracker.fitnesstracker.wear

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicInteger

/**
 * Kleine native helper tussen de Wear OS Data Layer en Flutter.
 *
 * - [send] stuurt een bericht naar alle verbonden horloges (MessageClient).
 * - [emit] geeft een binnenkomend bericht/data-item door aan Dart (EventChannel).
 *   Is Dart nog niet aan het luisteren, dan wacht een kleine buffer (max. [MAX_PENDING]).
 *
 * Protocol: zie docs/cadans-wear-design.md in de smartwatch-repo. Alle paden beginnen met [PREFIX].
 */
object WearBridge {
    private const val TAG = "WearBridge"
    const val PREFIX = "/cadans/v1/"
    const val PATH_PING = PREFIX + "ping"
    const val PATH_PONG = PREFIX + "pong"
    private const val MAX_PENDING = 50

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val pending = ArrayDeque<Map<String, Any?>>()

    fun attach(events: EventChannel.EventSink) {
        sink = events
        while (pending.isNotEmpty()) events.success(pending.removeFirst())
    }

    fun detach() {
        sink = null
    }

    /** Mag vanaf elke thread aangeroepen worden. */
    fun emit(kind: String, path: String, nodeId: String, data: ByteArray) {
        val event = mapOf<String, Any?>(
            "kind" to kind,
            "path" to path,
            "nodeId" to nodeId,
            "data" to data,
        )
        main.post {
            val s = sink
            if (s != null) {
                s.success(event)
            } else {
                if (pending.size >= MAX_PENDING) pending.removeFirst()
                pending.addLast(event)
            }
        }
    }

    /**
     * Stuurt [data] naar alle verbonden knooppunten. [done] krijgt (aantal verbonden,
     * aantal gelukt, foutcode of null) op de main-thread.
     */
    fun send(
        context: Context,
        path: String,
        data: ByteArray,
        done: (nodes: Int, sent: Int, error: String?) -> Unit,
    ) {
        val app = context.applicationContext
        Wearable.getNodeClient(app).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    done(0, 0, "no_connected_node")
                    return@addOnSuccessListener
                }
                val client = Wearable.getMessageClient(app)
                val remaining = AtomicInteger(nodes.size)
                val ok = AtomicInteger(0)
                nodes.forEach { node ->
                    client.sendMessage(node.id, path, data)
                        .addOnSuccessListener { ok.incrementAndGet() }
                        .addOnFailureListener { Log.w(TAG, "send to ${node.displayName} failed", it) }
                        .addOnCompleteListener {
                            if (remaining.decrementAndGet() == 0) {
                                done(nodes.size, ok.get(), if (ok.get() > 0) null else "send_failed")
                            }
                        }
                }
            }
            .addOnFailureListener {
                Log.w(TAG, "connectedNodes failed", it)
                done(0, 0, "nodes_failed")
            }
    }

    fun nodes(context: Context, done: (List<Map<String, Any?>>?) -> Unit) {
        Wearable.getNodeClient(context.applicationContext).connectedNodes
            .addOnSuccessListener { nodes ->
                done(nodes.map { mapOf("id" to it.id, "name" to it.displayName, "nearby" to it.isNearby) })
            }
            .addOnFailureListener { done(null) }
    }
}
