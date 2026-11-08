package com.orkitec.velorki.wear

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The watch held to `test/fixtures/watch/messages.json`, the file the
 * phone's tests (`watch_ride_bridge_test.dart`) hold the phone to: what the
 * phone sends decodes here as the screen needs it, and what this app sends
 * is exactly what the phone expects. Each map goes through the plugin's wire
 * format on the way, as it does between the devices.
 */
class WatchProtocolTest {
    private val fixture = JSONObject(
        javaClass.classLoader!!.getResource("messages.json")!!.readText(),
    )
    private val fromWatch = fixture.getJSONObject("watchToPhone")
    private val toWatch = fixture.getJSONObject("phoneToWatch")

    /** A fixture message as the phone's codec hands it to the plugin. */
    private fun map(json: JSONObject): Map<String, Any?> =
        json.keys().asSequence().associateWith { key ->
            when (val value = json.get(key)) {
                // Dart's StandardMessageCodec: an int that fits 32 bits is an
                // Integer, any other a Long.
                is Long -> if (value in Int.MIN_VALUE..Int.MAX_VALUE) value.toInt() else value
                else -> value
            }
        }

    /** Over the wire and back, as the plugin and this app write and read it. */
    private fun wire(message: Map<String, Any?>): Map<String, Any?> =
        WatchProtocol.decodeBytes(WatchProtocol.encode(message))!!

    private fun context(name: String) = WatchProtocol.decodeContext(wire(map(toWatch.getJSONObject(name))))

    @Test
    fun `the context of a ride with a turn ahead`() {
        assertEquals(
            RideContext(
                status = "active",
                distance = "3.2 km",
                elapsed = "00:42",
                speed = "18.0 km/h",
                turnIcon = "arrow.turn.up.left",
                turnLabel = "Turn left",
                turnDistance = "150 m",
                offRoute = false,
                cue = 0,
                accent = "#C8F542",
                rest = false,
            ),
            context("contextActive"),
        )
    }

    @Test
    fun `the context with no ride`() {
        assertEquals(RideContext(status = "idle", accent = "#C8F542"), context("contextIdle"))
    }

    @Test
    fun `a paused ride with the sensor resting`() {
        val context = context("contextPaused")
        assertEquals("paused", context.status)
        assertEquals(true, context.rest)
        assertEquals(true, RideState(context = context).paused)
        assertEquals(true, RideState(context = context).riding)
    }

    @Test
    fun `off the route, with a cue as a Long`() {
        val context = context("contextOffRoute")
        assertEquals(true, context.offRoute)
        assertEquals(1789725720000L, context.cue)
        assertEquals("", context.turnDistance)
    }

    @Test
    fun `the context as a message decodes as the data item does`() {
        val message = WatchProtocol.decode(wire(map(toWatch.getJSONObject("contextMessage"))))
        assertEquals(PhoneMessage.Context(context("contextActive")), message)
    }

    @Test
    fun `the phone asking for the workout`() {
        assertEquals(
            PhoneMessage.Workout(start = true),
            WatchProtocol.decode(wire(map(toWatch.getJSONObject("workoutStart")))),
        )
        assertEquals(
            PhoneMessage.Workout(start = false),
            WatchProtocol.decode(wire(map(toWatch.getJSONObject("workoutStop")))),
        )
    }

    @Test
    fun `what the watch sends is what the phone expects`() {
        assertEquals(map(fromWatch.getJSONObject("heartRate")), wire(WatchProtocol.heartRate(142, 1789725660000L)))
        // A Long, even for an instant that would fit an Integer: the phone
        // reads milliseconds since 1970.
        assertEquals(java.lang.Long::class.java, wire(WatchProtocol.heartRate(142, 1789725660000L))["at"]!!.javaClass)
        val commands = fromWatch.getJSONArray("commands")
        val sent = listOf(
            WatchProtocol.COMMAND_START,
            WatchProtocol.COMMAND_PAUSE,
            WatchProtocol.COMMAND_RESUME,
            WatchProtocol.COMMAND_STOP,
        ).map { wire(WatchProtocol.command(it)) }
        assertEquals((0 until commands.length()).map { map(commands.getJSONObject(it)) }, sent)
        assertEquals(map(fromWatch.getJSONObject("heartRateStopped")), wire(WatchProtocol.heartRateStopped()))
    }

    @Test
    fun `every turn icon the phone can send has a drawing`() {
        val icons: JSONArray = fixture.getJSONArray("turnIcons")
        for (i in 0 until icons.length()) {
            assertNotNull(icons.getString(i), turnIcon(icons.getString(i)))
        }
        assertNull(turnIcon(""))
    }

    @Test
    fun `a message of any other type is left alone`() {
        assertNull(WatchProtocol.decode(mapOf("type" to "somethingNew")))
        assertNull(WatchProtocol.decode(mapOf("type" to "workout", "action" to "dance")))
    }

    @Test
    fun `only a plain map is read off the wire`() {
        assertNull(WatchProtocol.decodeBytes(byteArrayOf(1, 2, 3)))
        val list = java.io.ByteArrayOutputStream().also {
            java.io.ObjectOutputStream(it).use { stream -> stream.writeObject(java.util.ArrayList(listOf("a"))) }
        }
        assertNull(WatchProtocol.decodeBytes(list.toByteArray()))
    }

    @Test
    fun `a figure's unit is split off as on the Apple Watch`() {
        assertEquals("23.8" to "km/h", splitUnit("23.8 km/h"))
        assertEquals("1:12:05" to null, splitUnit("1:12:05"))
        assertEquals("Turn left" to null, splitUnit("Turn left"))
        assertEquals("150" to "m", splitUnit("150 m"))
        assertEquals("00:42" to null, splitUnit("00:42"))
    }
}
