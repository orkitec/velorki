package com.orkitec.velorki.wear

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * The foreground service that keeps this app, and with it the exercise's
 * updates, alive with the wrist down, and the Ongoing Activity that keeps
 * the ride on the watch face: Riding or Paused and the time, a tap away from
 * this app. Runs while the phone reports a ride or the sensor measures.
 */
class RideService : LifecycleService() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, getString(R.string.notification_channel), NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_ongoing)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(statusText(Wear.session(this).state.value))
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(open)
        val ongoing = OngoingActivity.Builder(this, NOTIFICATION, builder)
            .setStaticIcon(R.drawable.ic_ongoing)
            .setTouchIntent(open)
            .setStatus(status(Wear.session(this).state.value))
            .build()
        ongoing.apply(this)
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION,
                builder.build(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH,
            )
        } catch (e: Exception) {
            // No heart rate permission yet, or started from the background
            // where Android does not allow it: tried again when either
            // changes.
            Wear.log("Ride service could not go to the foreground: ${e.message}")
            stopSelf()
            return
        }
        lifecycleScope.launch {
            Wear.session(this@RideService).state.map(::statusText).distinctUntilChanged().collect { text ->
                ongoing.update(this@RideService, Status.Builder().addTemplate(text).build())
            }
        }
    }

    private fun status(state: RideState) = Status.Builder().addTemplate(statusText(state)).build()

    /** Riding or Paused, then the ride's time as the phone reports it. */
    private fun statusText(state: RideState): String {
        val title = getString(if (state.paused) R.string.title_paused else R.string.title_riding)
        val elapsed = state.context.elapsed
        return if (elapsed.isEmpty()) title else "$title · $elapsed"
    }

    companion object {
        private const val CHANNEL = "ride"
        private const val NOTIFICATION = 1

        fun start(context: Context) {
            try {
                context.startForegroundService(Intent(context, RideService::class.java))
            } catch (e: Exception) {
                // Android refuses a foreground service started from the
                // background in some states; the ride still shows when the
                // app is opened, and the exercise runs without it.
                Wear.log("Ride service would not start: ${e.message}")
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RideService::class.java))
        }
    }
}
