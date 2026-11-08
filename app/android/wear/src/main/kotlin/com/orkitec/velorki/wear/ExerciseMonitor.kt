package com.orkitec.velorki.wear

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.concurrent.futures.await
import androidx.core.content.ContextCompat
import androidx.health.services.client.ExerciseClient
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseTrackedStatus
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.math.roundToInt

/** The permission the heart rate needs on this watch. */
val heartRatePermission: String
    get() = if (Build.VERSION.SDK_INT >= 36) {
        "android.permission.health.READ_HEART_RATE"
    } else {
        Manifest.permission.BODY_SENSORS
    }

/**
 * The heart rate through Health Services: a cycling exercise, which keeps the
 * sensor measuring with the wrist down. No location (the phone records the
 * track) and no auto-pause (the phone decides that and says so in its
 * context). Health Services writes nothing to Health Connect by itself, and
 * this app writes nothing either: the phone saves the ride.
 */
class ExerciseMonitor(
    private val context: Context,
    private val scope: CoroutineScope,
    private val log: (String) -> Unit,
) : HeartRateMonitor {
    override var listener: HeartRateMonitor.Listener? = null

    private val client: ExerciseClient by lazy {
        HealthServices.getClient(context).exerciseClient
    }

    /** Whether this monitor has an exercise going, so a foreign one is left alone. */
    private var ours = false

    /** A little before this monitor's exercise started. */
    private var startedAfter: Instant = Instant.EPOCH

    private val callback = object : ExerciseUpdateCallback {
        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            val bpm = update.latestMetrics.getData(DataType.HEART_RATE_BPM)
                .lastOrNull()?.value?.roundToInt()
            if (bpm != null) listener?.onHeartRate(bpm)
            // The end of an exercise started before this one (a process that
            // went before this one left it) is not this one's end.
            val older = update.startTime?.isBefore(startedAfter) ?: false
            if (update.exerciseStateInfo.state.isEnded && ours && !older) {
                ours = false
                listener?.onEnded()
            }
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) {}

        override fun onRegistered() {}

        override fun onRegistrationFailed(throwable: Throwable) {
            log("Exercise callback failed: ${throwable.message}")
        }

        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {}
    }

    override fun start() {
        if (ContextCompat.checkSelfPermission(context, heartRatePermission) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            listener?.onStartFailed(Problem.HealthAccess)
            return
        }
        scope.launch {
            try {
                val capabilities = client.getCapabilitiesAsync().await()
                val biking = capabilities.typeToCapabilities[ExerciseType.BIKING]
                if (biking == null || DataType.HEART_RATE_BPM !in biking.supportedDataTypes) {
                    listener?.onStartFailed(Problem.WouldNotStart("no heart rate for cycling"))
                    return@launch
                }
                client.setUpdateCallback(callback)
                // This app's exercise outlives its process: a process the
                // system ended mid-ride finds it still running, and carries
                // on with it rather than start a second one, whose start
                // would report the first one's end.
                val current = client.getCurrentExerciseInfoAsync().await()
                if (current.exerciseTrackedStatus == ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS) {
                    log("Carrying on with the exercise already running")
                    try {
                        client.resumeExerciseAsync().await()
                    } catch (e: Exception) {
                        // Not paused.
                    }
                    startedAfter = Instant.EPOCH
                    ours = true
                    listener?.onStarted()
                    return@launch
                }
                val config = ExerciseConfig.builder(ExerciseType.BIKING)
                    .setDataTypes(setOf(DataType.HEART_RATE_BPM))
                    .setIsAutoPauseAndResumeEnabled(false)
                    .setIsGpsEnabled(false)
                    .build()
                startedAfter = Instant.now().minusSeconds(5)
                client.startExerciseAsync(config).await()
                ours = true
                listener?.onStarted()
            } catch (e: Exception) {
                log("Exercise would not start: ${e.message}")
                listener?.onStartFailed(Problem.WouldNotStart(e.message ?: e.javaClass.simpleName))
            }
        }
    }

    override fun pause() = call("pause") { client.pauseExerciseAsync().await() }

    override fun resume() = call("resume") { client.resumeExerciseAsync().await() }

    override fun end() {
        if (!ours) return
        ours = false
        call("end") {
            client.endExerciseAsync().await()
            client.clearUpdateCallbackAsync(callback).await()
        }
    }

    private fun call(what: String, body: suspend () -> Unit) {
        scope.launch {
            try {
                body()
            } catch (e: Exception) {
                log("Exercise $what failed: ${e.message}")
                if (what != "end") listener?.onFailed(e.message ?: e.javaClass.simpleName)
            }
        }
    }
}
