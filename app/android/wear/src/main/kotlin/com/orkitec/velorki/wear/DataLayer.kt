package com.orkitec.velorki.wear

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * The phone over the Wear OS Data Layer, as the `watch_connectivity` plugin
 * on the phone has it: a message to every connected node on
 * [WatchProtocol.PATH]. The phone's app is the only one that listens there.
 */
class DataLayerLink(
    private val context: Context,
    private val scope: CoroutineScope,
    private val log: (String) -> Unit,
) : PhoneLink {
    override fun send(message: Map<String, Any>) {
        log("To the phone: $message")
        scope.launch {
            try {
                val nodes = Wearable.getNodeClient(context).connectedNodes.await()
                val bytes = WatchProtocol.encode(message)
                for (node in nodes) {
                    Wearable.getMessageClient(context)
                        .sendMessage(node.id, WatchProtocol.PATH, bytes).await()
                }
            } catch (e: Exception) {
                log("Send failed: ${e.message}")
            }
        }
    }

    /**
     * The context the phone last put up, for an app opened mid-ride: the
     * data item every phone keeps at `/watch_connectivity`, newest wins.
     */
    suspend fun lastContext(): RideContext? = try {
        val local = Wearable.getNodeClient(context).localNode.await().id
        val items = Wearable.getDataClient(context)
            .getDataItems(Uri.parse("wear://*/${WatchProtocol.PATH}")).await()
        try {
            items.filter { it.uri.host != local }
                .firstNotNullOfOrNull(::decode)
                ?.let(WatchProtocol::decodeContext)
        } finally {
            items.release()
        }
    } catch (e: Exception) {
        log("Reading the context failed: ${e.message}")
        null
    }
}

private fun decode(item: DataItem): Map<String, Any?>? = item.data?.let(WatchProtocol::decodeBytes)

/**
 * Where the Data Layer delivers what the phone sends, running or not: a
 * message wakes this app, which is how a ride started on the phone reaches a
 * watch app nobody opened. Called on a binder thread; the session is handed
 * everything on the main one.
 */
class PhoneListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path.trimStart('/') != WatchProtocol.PATH) return
        val message = WatchProtocol.decodeBytes(event.data) ?: return
        val decoded = WatchProtocol.decode(message) ?: return
        Wear.scope.launch { Wear.session(this@PhoneListenerService).receive(decoded) }
    }

    override fun onDataChanged(events: DataEventBuffer) {
        val contexts = events
            .filter { it.type == DataEvent.TYPE_CHANGED && it.dataItem.uri.path?.trimStart('/') == WatchProtocol.PATH }
            .mapNotNull { decode(it.dataItem) }
        Wear.scope.launch {
            val session = Wear.session(this@PhoneListenerService)
            for (context in contexts) session.apply(WatchProtocol.decodeContext(context))
        }
    }
}
