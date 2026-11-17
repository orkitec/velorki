package com.orkitec.velorki.wear

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A sensor the test runs by hand. */
private class FakeMonitor : HeartRateMonitor {
    override var listener: HeartRateMonitor.Listener? = null
    val calls = mutableListOf<String>()

    override fun start() {
        calls += "start"
    }

    override fun pause() {
        calls += "pause"
    }

    override fun resume() {
        calls += "resume"
    }

    override fun end() {
        calls += "end"
    }
}

/**
 * The rules of `RideSession.swift`, held on this side: the watch measures
 * while the phone rides, pauses with it, rests when asked to, and repeats a
 * command until the phone shows it done.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RideSessionTest {
    private val sent = mutableListOf<Map<String, Any>>()
    private val haptics = mutableListOf<Boolean>()
    private val monitor = FakeMonitor()
    private var clock = 1_000_000L

    private fun TestScope.session() = RideSession(
        scope = this,
        phone = { sent += it },
        monitor = monitor,
        haptics = { haptics += it },
        now = { clock },
    )

    private val active = RideContext(status = "active")
    private val paused = RideContext(status = "paused")
    private val idle = RideContext(status = "idle")

    private fun commands() = sent.filter { it["type"] == "command" }.map { it["command"] }

    @Test
    fun `a ride reported running starts the measuring by itself`() = runTest {
        val session = session()
        session.apply(active)
        assertEquals(listOf("start"), monitor.calls)
        session.onStarted()
        assertTrue(session.state.value.measuring)
    }

    @Test
    fun `the phone asking for the workout starts and ends it`() = runTest {
        val session = session()
        session.receive(PhoneMessage.Workout(start = true))
        session.onStarted()
        session.receive(PhoneMessage.Workout(start = false))
        assertEquals(listOf("start", "end"), monitor.calls)
        assertFalse(session.state.value.measuring)
    }

    @Test
    fun `a pause pauses the workout, and the ride going on resumes it`() = runTest {
        val session = session()
        session.apply(active)
        session.onStarted()
        session.onHeartRate(140)
        session.apply(paused)
        session.apply(active)
        assertEquals(listOf("start", "pause", "resume"), monitor.calls)
        assertEquals(140, session.state.value.heartRate)
    }

    @Test
    fun `resting the sensor ends the workout at a pause and keeps the reading`() = runTest {
        val session = session()
        session.apply(active)
        session.onStarted()
        session.onHeartRate(140)
        session.apply(paused.copy(rest = true))
        assertEquals(listOf("start", "end"), monitor.calls)
        assertEquals(140, session.state.value.heartRate)
        assertFalse(session.state.value.measuring)
        // The phone wakes the watch when the ride goes on.
        session.receive(PhoneMessage.Workout(start = true))
        assertEquals(listOf("start", "end", "start"), monitor.calls)
    }

    @Test
    fun `the ride over ends the workout, and its reading goes`() = runTest {
        val session = session()
        session.apply(active)
        session.onStarted()
        session.onHeartRate(140)
        session.apply(idle)
        assertEquals(listOf("start", "end"), monitor.calls)
        assertNull(session.state.value.heartRate)
    }

    @Test
    fun `stop heart rate ends the workout, tells the phone, and stays stopped`() = runTest {
        val session = session()
        session.apply(active)
        session.onStarted()
        session.stopHeartRate()
        assertEquals(mapOf("type" to "heartRateStopped"), sent.last())
        session.apply(active)
        assertEquals(listOf("start", "end"), monitor.calls)
        session.startHeartRate()
        assertEquals(listOf("start", "end", "start"), monitor.calls)
    }

    @Test
    fun `the heart rate goes to the phone at most once a second`() = runTest {
        val session = session()
        session.apply(active)
        session.onStarted()
        session.onHeartRate(140)
        clock += 400
        session.onHeartRate(141)
        clock += 700
        session.onHeartRate(142)
        val readings = sent.filter { it["type"] == "heartRate" }
        assertEquals(listOf(140, 142), readings.map { it["bpm"] })
        assertEquals(1_001_100L, readings.last()["at"])
        assertEquals(142, session.state.value.heartRate)
    }

    @Test
    fun `a command is resent until the phone shows it done`() = runTest {
        val session = session()
        session.pause()
        advanceTimeBy(RideSession.RETRY_EVERY_MS * 2 + 1)
        assertEquals(listOf("pause", "pause", "pause"), commands())
        session.apply(paused)
        advanceTimeBy(RideSession.RETRY_EVERY_MS * 3)
        assertEquals(3, commands().size)
    }

    @Test
    fun `a command never confirmed is said on the wrist`() = runTest {
        val session = session()
        session.resume()
        advanceTimeBy(RideSession.RETRY_EVERY_MS * RideSession.RETRIES + 1)
        runCurrent()
        assertEquals(RideSession.RETRIES, commands().size)
        assertEquals(Problem.PhoneSilent, session.state.value.problem)
    }

    @Test
    fun `start sends the command and measures, finish ends both`() = runTest {
        val session = session()
        session.start()
        session.onStarted()
        session.apply(active)
        session.stop()
        session.apply(idle)
        assertEquals(listOf("start", "stop"), commands())
        assertEquals(listOf("start", "end"), monitor.calls)
        advanceTimeBy(RideSession.RETRY_EVERY_MS * 10)
        assertEquals(2, commands().size)
    }

    @Test
    fun `one buzz per cue, the failure one off the route`() = runTest {
        val session = session()
        session.apply(active.copy(cue = 5))
        session.apply(active.copy(cue = 5))
        session.apply(active.copy(cue = 9, offRoute = true))
        session.apply(active.copy(cue = 0))
        assertEquals(listOf(false, true), haptics)
    }

    @Test
    fun `a missing permission waits for the rider, then measures`() = runTest {
        val session = session()
        session.apply(active)
        session.onStartFailed(Problem.HealthAccess)
        assertEquals(Problem.HealthAccess, session.state.value.problem)
        session.accessGranted()
        assertNull(session.state.value.problem)
        assertEquals(listOf("start", "start"), monitor.calls)
    }

    @Test
    fun `a workout that ends on its own takes its reading, unless paused`() = runTest {
        val session = session()
        session.apply(active)
        session.onStarted()
        session.onHeartRate(150)
        session.onEnded()
        assertNull(session.state.value.heartRate)
        assertFalse(session.state.value.measuring)
    }

    @Test
    fun `a workout ended while it was starting is ended once it has`() = runTest {
        val session = session()
        session.apply(active)
        session.apply(idle)
        session.onStarted()
        assertEquals(listOf("start", "end"), monitor.calls)
        assertFalse(session.state.value.measuring)
    }
}
