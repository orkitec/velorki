package com.orkitec.velorki.wear

import com.orkitec.velorki.wear.WatchProtocol.COMMAND_PAUSE
import com.orkitec.velorki.wear.WatchProtocol.COMMAND_RESUME
import com.orkitec.velorki.wear.WatchProtocol.COMMAND_START
import com.orkitec.velorki.wear.WatchProtocol.COMMAND_STOP
import com.orkitec.velorki.wear.WatchProtocol.STATUS_ACTIVE
import com.orkitec.velorki.wear.WatchProtocol.STATUS_IDLE
import com.orkitec.velorki.wear.WatchProtocol.STATUS_PAUSED
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Where the phone is: what this app sends goes through here. */
fun interface PhoneLink {
    fun send(message: Map<String, Any>)
}

/** The buzz on the wrist for a cue: [failure] while off the route. */
fun interface Haptics {
    fun play(failure: Boolean)
}

/**
 * The watch's own heart rate sensor, kept measuring with the wrist down by a
 * workout the OS runs: Health Services' exercise on Wear OS. Calls back into
 * its [Listener] on the main thread.
 */
interface HeartRateMonitor {
    var listener: Listener?

    /** Starts a cycling workout; answers with [Listener.onStarted] or [Listener.onStartFailed]. */
    fun start()
    fun pause()
    fun resume()

    /** Ends the workout. Nothing of it is kept: the phone writes the ride. */
    fun end()

    interface Listener {
        fun onStarted()
        fun onStartFailed(problem: Problem)
        fun onHeartRate(bpm: Int)

        /** The workout ended without being asked to, or was ended. */
        fun onEnded()
        fun onFailed(detail: String)
    }
}

/** Why there is no heart rate, when the watch knows. Shown under the heart. */
sealed interface Problem {
    /** The heart rate permission was refused. */
    data object HealthAccess : Problem
    data class WouldNotStart(val detail: String) : Problem
    data class Stopped(val detail: String) : Problem

    /** A command the phone never confirmed. */
    data object PhoneSilent : Problem
}

/** Everything the screen is drawn from. */
data class RideState(
    val context: RideContext = RideContext(),
    val heartRate: Int? = null,
    val measuring: Boolean = false,
    val problem: Problem? = null,
) {
    /** The ride is paused; the last reading stays on screen, dimmed. */
    val paused: Boolean get() = context.status == STATUS_PAUSED

    /** The phone is running a ride, paused or not. */
    val riding: Boolean get() = context.status == STATUS_ACTIVE || paused
}

/**
 * The ride as the watch knows it: what the phone last reported, and the
 * heart rate the watch itself is measuring.
 *
 * The same rules as the Apple Watch app's `RideSession.swift`, line for line
 * where the platforms allow: the watch is a display and a sensor, never a
 * second recorder. The phone's context is the screen; its messages ask for
 * the workout to start or stop; the buttons send commands back, each resent
 * until the phone's context shows it done.
 */
class RideSession(
    private val scope: CoroutineScope,
    private val phone: PhoneLink,
    private val monitor: HeartRateMonitor,
    private val haptics: Haptics,
    private val now: () -> Long = System::currentTimeMillis,
    private val log: (String) -> Unit = {},
) : HeartRateMonitor.Listener {
    private val _state = MutableStateFlow(RideState())
    val state: StateFlow<RideState> = _state.asStateFlow()

    private enum class Workout { NONE, STARTING, RUNNING, PAUSED }

    private var workout = Workout.NONE

    /**
     * Set by "Stop heart rate", cleared when the ride ends: a ride the phone
     * reports as running starts the measuring again on its own unless the
     * rider stopped it on purpose.
     */
    private var stoppedByRider = false

    /** The cue the last haptic was played for, so each one is felt once. */
    private var lastCue = 0L

    /** When the last reading went to the phone: one a second is enough. */
    private var lastSent: Long? = null

    /**
     * A command the phone has not confirmed yet, resent until its context
     * shows a status it leads to. A phone app that only starts listening a
     * moment after the first message loses that one; a later one lands.
     */
    private data class Pending(val command: String, val expects: Set<String>, val tries: Int)

    private var pending: Pending? = null
    private var retry: Job? = null

    /**
     * A workout asked for while the heart rate permission was missing; it
     * starts once the rider grants it.
     */
    private var awaitingAccess = false

    init {
        monitor.listener = this
    }

    // the buttons

    /** Starts a ride: the phone records it, the watch measures it. */
    fun start() {
        log("Start tapped")
        command(COMMAND_START, setOf(STATUS_ACTIVE, STATUS_PAUSED))
        startWorkout()
    }

    /** Suspends the ride on the phone. The watch keeps measuring. */
    fun pause() = command(COMMAND_PAUSE, setOf(STATUS_PAUSED))

    fun resume() = command(COMMAND_RESUME, setOf(STATUS_ACTIVE))

    /** Ends the ride; the phone names it on a sheet, so it stops and waits. */
    fun stop() {
        log("Finish tapped")
        command(COMMAND_STOP, setOf(STATUS_IDLE))
        endWorkout("finish tapped")
    }

    /** Stops measuring without ending the ride, to save the watch's battery. */
    fun stopHeartRate() {
        stoppedByRider = true
        endWorkout("stop heart rate tapped")
        phone.send(WatchProtocol.heartRateStopped())
    }

    /** Starts measuring again mid-ride. */
    fun startHeartRate() {
        stoppedByRider = false
        startWorkout()
    }

    /** The rider granted the heart rate permission the workout waited for. */
    fun accessGranted() {
        if (!awaitingAccess) return
        awaitingAccess = false
        _state.update { it.copy(problem = null) }
        if (!stoppedByRider) startWorkout()
    }

    // the phone

    /** A message or the context from the phone. */
    fun receive(message: PhoneMessage) = when (message) {
        is PhoneMessage.Context -> apply(message.context)
        is PhoneMessage.Workout -> {
            log("Phone asks workout ${if (message.start) "start" else "stop"}")
            if (message.start) startWorkout() else endWorkout("phone asked")
        }
    }

    fun apply(context: RideContext) {
        val status = context.status
        log("Context: status $status, workout $workout")
        _state.update { it.copy(context = context) }
        confirm(status)
        // The phone may have ended the ride while this app was out of reach
        // for its stop message; the context says so, and the workout goes.
        if (status == STATUS_IDLE) {
            stoppedByRider = false
            if (workout != Workout.NONE) endWorkout("phone reports the ride over")
        }
        // A paused ride pauses the workout rather than ending it, unless the
        // rider chose to rest the sensor; then it ends, and the phone wakes
        // this app again when the ride goes on.
        if (status == STATUS_PAUSED && context.rest && workout != Workout.NONE) {
            endWorkout("paused, resting the sensor", keepReading = true)
        } else if (status == STATUS_PAUSED && workout == Workout.RUNNING) {
            workout = Workout.PAUSED
            monitor.pause()
        } else if (status == STATUS_ACTIVE && workout == Workout.PAUSED) {
            workout = Workout.RUNNING
            monitor.resume()
        }
        // A ride running while this app is not measuring (opened late, or
        // woken by the phone) starts measuring by itself.
        if (status == STATUS_ACTIVE && workout == Workout.NONE && !stoppedByRider) startWorkout()
        feel(context.cue, context.offRoute)
    }

    // the workout

    private fun startWorkout() {
        if (workout != Workout.NONE) return
        workout = Workout.STARTING
        monitor.start()
    }

    private fun endWorkout(reason: String, keepReading: Boolean = false) {
        log("End asked for: $reason; workout $workout")
        if (workout == Workout.NONE) return
        // A workout still starting has nothing to end yet; onStarted ends it.
        val starting = workout == Workout.STARTING
        workout = Workout.NONE
        _state.update {
            it.copy(measuring = false, heartRate = if (keepReading) it.heartRate else null)
        }
        if (!starting) monitor.end()
    }

    override fun onStarted() {
        if (workout != Workout.STARTING) {
            // Ended while it was starting: the rider or the phone changed
            // their mind.
            monitor.end()
            return
        }
        workout = Workout.RUNNING
        lastSent = null
        _state.update { it.copy(measuring = true, problem = null) }
        log("Workout started")
        // The ride may have paused while the workout was starting.
        if (state.value.paused) {
            workout = Workout.PAUSED
            monitor.pause()
        }
    }

    override fun onStartFailed(problem: Problem) {
        log("Workout would not start: $problem")
        if (workout == Workout.STARTING) workout = Workout.NONE
        awaitingAccess = problem == Problem.HealthAccess
        _state.update { it.copy(problem = problem) }
    }

    override fun onHeartRate(bpm: Int) {
        if (bpm <= 0 || workout == Workout.NONE) return
        _state.update { it.copy(heartRate = bpm) }
        val at = now()
        val sent = lastSent
        if (sent != null && at - sent < 1000) return
        lastSent = at
        phone.send(WatchProtocol.heartRate(bpm, at))
    }

    override fun onEnded() {
        log("Workout ended")
        workout = Workout.NONE
        // A workout that ended on its own, not for a pause, takes its
        // reading with it.
        _state.update { it.copy(measuring = false, heartRate = if (it.paused) it.heartRate else null) }
    }

    override fun onFailed(detail: String) {
        log("Workout failed: $detail")
        endWorkout("workout failed")
        _state.update { it.copy(problem = Problem.Stopped(detail)) }
    }

    // talking to the phone

    private fun command(command: String, expects: Set<String>) {
        pending = Pending(command, expects, 0)
        resend()
    }

    private fun resend() {
        retry?.cancel()
        retry = null
        val current = pending ?: return
        if (current.tries >= RETRIES) {
            log("Command ${current.command} never confirmed")
            pending = null
            // A phone app that is not running, or a phone out of range,
            // hears nothing: only the rider can help, so the wrist says so.
            _state.update { it.copy(problem = Problem.PhoneSilent) }
            return
        }
        pending = current.copy(tries = current.tries + 1)
        phone.send(WatchProtocol.command(current.command))
        retry = scope.launch {
            delay(RETRY_EVERY_MS)
            resend()
        }
    }

    /** The phone's status has come in: a command it confirms is done with. */
    private fun confirm(status: String) {
        val current = pending ?: return
        if (status !in current.expects) return
        if (current.tries > 1) log("Command ${current.command} confirmed on try ${current.tries}")
        pending = null
        retry?.cancel()
        retry = null
        _state.update { if (it.problem == Problem.PhoneSilent) it.copy(problem = null) else it }
    }

    /** One haptic per cue the phone reports, however many were missed. */
    private fun feel(cue: Long, offRoute: Boolean) {
        if (cue <= 0 || cue == lastCue) return
        lastCue = cue
        haptics.play(failure = offRoute)
    }

    companion object {
        const val RETRY_EVERY_MS = 2000L
        const val RETRIES = 8
    }
}
