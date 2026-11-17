package com.orkitec.velorki.wear

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InvalidClassException
import java.io.ObjectInputStream
import java.io.ObjectOutputStream
import java.io.ObjectStreamClass

/**
 * Everything the phone and this app say to each other: the keys of
 * `lib/features/sensors/data/watch_protocol.dart`, spelled out once more.
 *
 * `test/fixtures/watch/messages.json` has one example of every message;
 * the phone's tests and [WatchProtocolTest] both hold their code to it, so a
 * key changed on one side and not the other fails a test.
 *
 * The transport is the `watch_connectivity` plugin's on Android: a message
 * goes over the Data Layer's `MessageClient` on [PATH], and the context is a
 * `DataItem` at `/`[PATH]; both carry a `java.util.HashMap` written with
 * `ObjectOutputStream`, which is what the plugin reads and writes.
 */
object WatchProtocol {
    /** The message path, and the data item's without its leading slash. */
    const val PATH = "watch_connectivity"

    const val TYPE = "type"

    // watch → phone
    const val TYPE_HEART_RATE = "heartRate"
    const val BPM = "bpm"
    const val AT = "at"
    const val TYPE_COMMAND = "command"
    const val COMMAND = "command"
    const val COMMAND_START = "start"
    const val COMMAND_PAUSE = "pause"
    const val COMMAND_RESUME = "resume"
    const val COMMAND_STOP = "stop"
    const val TYPE_HEART_RATE_STOPPED = "heartRateStopped"

    // phone → watch
    const val TYPE_WORKOUT = "workout"
    const val WORKOUT_ACTION = "action"
    const val WORKOUT_START = "start"
    const val WORKOUT_STOP = "stop"

    /** The context again as a message, which Wear OS delivers at once. */
    const val TYPE_CONTEXT = "context"

    // the context
    const val STATUS = "status"
    const val STATUS_IDLE = "idle"
    const val STATUS_ACTIVE = "active"
    const val STATUS_PAUSED = "paused"
    const val DISTANCE = "distance"
    const val ELAPSED = "elapsed"
    const val SPEED = "speed"
    const val TURN_ICON = "turnIcon"
    const val TURN_LABEL = "turnLabel"
    const val TURN_DISTANCE = "turnDistance"
    const val OFF_ROUTE = "offRoute"
    const val CUE = "cue"
    const val ACCENT = "accent"
    const val REST = "rest"

    fun heartRate(bpm: Int, at: Long): Map<String, Any> =
        mapOf(TYPE to TYPE_HEART_RATE, BPM to bpm, AT to at)

    fun command(command: String): Map<String, Any> =
        mapOf(TYPE to TYPE_COMMAND, COMMAND to command)

    fun heartRateStopped(): Map<String, Any> = mapOf(TYPE to TYPE_HEART_RATE_STOPPED)

    /** What a message from the phone asks for, or null for one this app ignores. */
    fun decode(message: Map<String, Any?>): PhoneMessage? = when (message[TYPE]) {
        TYPE_WORKOUT -> when (message[WORKOUT_ACTION]) {
            WORKOUT_START -> PhoneMessage.Workout(start = true)
            WORKOUT_STOP -> PhoneMessage.Workout(start = false)
            else -> null
        }
        TYPE_CONTEXT -> PhoneMessage.Context(decodeContext(message))
        else -> null
    }

    /** The phone's context; anything missing reads as the Apple app reads it. */
    fun decodeContext(context: Map<String, Any?>) = RideContext(
        status = context[STATUS] as? String ?: STATUS_IDLE,
        distance = context[DISTANCE] as? String ?: "",
        elapsed = context[ELAPSED] as? String ?: "",
        speed = context[SPEED] as? String ?: "",
        turnIcon = context[TURN_ICON] as? String ?: "",
        turnLabel = context[TURN_LABEL] as? String ?: "",
        turnDistance = context[TURN_DISTANCE] as? String ?: "",
        offRoute = context[OFF_ROUTE] as? Boolean ?: false,
        // An Integer for 0, a Long for a real instant: the phone's codec
        // picks the smaller.
        cue = (context[CUE] as? Number)?.toLong() ?: 0L,
        accent = context[ACCENT] as? String ?: "",
        rest = context[REST] as? Boolean ?: false,
    )

    /** A map as the plugin puts it on the wire. */
    fun encode(map: Map<String, Any?>): ByteArray {
        val bytes = ByteArrayOutputStream()
        ObjectOutputStream(bytes).use { it.writeObject(HashMap(map)) }
        return bytes.toByteArray()
    }

    /**
     * A map off the wire, or null for anything else. Only the classes a
     * Flutter map of strings, numbers and booleans turns into are read.
     */
    fun decodeBytes(bytes: ByteArray): Map<String, Any?>? = try {
        PlainObjectInputStream(ByteArrayInputStream(bytes)).use { stream ->
            @Suppress("UNCHECKED_CAST")
            (stream.readObject() as? Map<*, *>)
                ?.filterKeys { it is String } as Map<String, Any?>?
        }
    } catch (e: Exception) {
        null
    }
}

/** Java deserialisation of a plain map, and of nothing else. */
private class PlainObjectInputStream(input: ByteArrayInputStream) : ObjectInputStream(input) {
    override fun resolveClass(desc: ObjectStreamClass): Class<*> {
        if (desc.name !in allowed) throw InvalidClassException(desc.name, "not a plain value")
        return super.resolveClass(desc)
    }

    private companion object {
        val allowed = setOf(
            "java.util.HashMap",
            "java.lang.String",
            "java.lang.Number",
            "java.lang.Integer",
            "java.lang.Long",
            "java.lang.Double",
            "java.lang.Boolean",
        )
    }
}

/** What the phone last reported: the ride as the screen draws it. */
data class RideContext(
    val status: String = WatchProtocol.STATUS_IDLE,
    val distance: String = "",
    val elapsed: String = "",
    val speed: String = "",
    val turnIcon: String = "",
    val turnLabel: String = "",
    val turnDistance: String = "",
    val offRoute: Boolean = false,
    /** Milliseconds since the epoch of the last cue to feel, 0 for none. */
    val cue: Long = 0L,
    /** `#RRGGBB`, empty until the phone has said. */
    val accent: String = "",
    /** The phone's "Rest the sensor while paused" switch. */
    val rest: Boolean = false,
)

sealed interface PhoneMessage {
    data class Workout(val start: Boolean) : PhoneMessage
    data class Context(val context: RideContext) : PhoneMessage
}
