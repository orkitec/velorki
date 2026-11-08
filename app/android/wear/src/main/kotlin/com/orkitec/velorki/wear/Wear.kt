package com.orkitec.velorki.wear

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * The one session the app has, shared by the screen, the listener service
 * and the ride service. Everything it shows comes from the phone and
 * everything it measures goes back to it, so nothing is stored.
 */
object Wear {
    private const val TAG = "VelorkiWatch"

    /** The main thread: the session is only ever touched from there. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var session: RideSession? = null

    fun log(line: String) {
        Log.i(TAG, line)
    }

    fun session(context: Context): RideSession = session ?: create(context.applicationContext)

    private fun create(context: Context): RideSession {
        val link = DataLayerLink(context, scope, ::log)
        val session = RideSession(
            scope = scope,
            phone = link,
            monitor = ExerciseMonitor(context, scope, ::log),
            haptics = VibratorHaptics(context),
            log = ::log,
        )
        this.session = session
        // Whatever the phone last said is waiting in its data item; an app
        // opened mid-ride shows the ride rather than an empty screen.
        scope.launch { link.lastContext()?.let(session::apply) }
        // The ongoing activity, and the foreground service behind it, for as
        // long as a ride runs or the sensor measures. Asked again when the
        // measuring starts, which may be what it waited for.
        scope.launch {
            session.state.map { it.riding to it.measuring }.distinctUntilChanged().collect { (riding, measuring) ->
                if (riding || measuring) RideService.start(context) else RideService.stop(context)
            }
        }
        return session
    }
}

/** The wrist's two buzzes: a click for a turn, a longer one off the route. */
private class VibratorHaptics(context: Context) : Haptics {
    private val vibrator = context.getSystemService(Vibrator::class.java)

    override fun play(failure: Boolean) {
        val effect = if (failure) {
            VibrationEffect.createWaveform(longArrayOf(0, 120, 80, 120, 80, 240), -1)
        } else {
            VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK)
        }
        vibrator?.vibrate(effect)
    }
}
