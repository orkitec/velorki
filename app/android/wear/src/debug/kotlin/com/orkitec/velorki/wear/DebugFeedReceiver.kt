package com.orkitec.velorki.wear

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Base64
import org.json.JSONObject

/**
 * Plays the phone from adb, in debug builds only: pairing an emulator needs
 * a Play Store phone, an account and the companion app.
 *
 *     adb shell am broadcast -a com.orkitec.velorki.wear.debug.FEED \
 *       -p com.orkitec.velorki --es b64 <base64 of a JSON message>
 *
 * A message with a `type` is handled as the phone's message is; one without
 * is the context, as the phone's data item. What the app sends back is in
 * logcat under "VelorkiWatch" ("To the phone: ...").
 */
class DebugFeedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val text = intent.getStringExtra("b64")?.let { String(Base64.decode(it, Base64.DEFAULT)) }
            ?: intent.getStringExtra("json")
            ?: return
        val json = JSONObject(text)
        val message = json.keys().asSequence().associateWith { json.get(it) }
        Wear.log("From adb: $message")
        val session = Wear.session(context)
        if (message.containsKey(WatchProtocol.TYPE)) {
            WatchProtocol.decode(message)?.let(session::receive)
        } else {
            session.apply(WatchProtocol.decodeContext(message))
        }
    }
}
