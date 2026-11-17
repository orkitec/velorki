/// Everything the phone and the watch app say to each other.
///
/// The other half of this file is Swift, in `ios/VelorkiWatch/`, and Kotlin,
/// in `android/wear/` (`WatchProtocol.kt`); the Apple app's README spells the
/// messages out in prose. Change a key here and change it there. One example
/// of every message is in `test/fixtures/watch/messages.json`, which the
/// tests of this side and the Wear OS app's JVM tests both hold their code
/// to, so those two cannot drift apart; the Swift is checked by hand.
///
/// On Wear OS the `watch_connectivity` plugin carries a message over the
/// Data Layer's `MessageClient` and the context as a `DataItem` at
/// `/watch_connectivity`, each a Java-serialised `HashMap`.
///
/// Two transports, because WatchConnectivity gives two and they mean different
/// things. A *message* is an event that matters once — a heart rate, a button
/// on the wrist — and is dropped when the other side is not reachable. The
/// *application context* is one dictionary of which only the latest copy
/// survives, which is exactly what a display wants: a watch that was asleep
/// for a minute wakes up with the current figures rather than a minute of old
/// ones.
library;

/// The key every message is tagged with.
const String watchTypeKey = 'type';

// --------------------------------------------------------- watch → phone

/// `{"type": "heartRate", "bpm": 142, "at": <ms since epoch>}`, about once a
/// second while the watch's workout session runs.
const String watchHeartRateType = 'heartRate';

/// Beats per minute, an integer.
const String watchBpmKey = 'bpm';

/// When the reading was taken, in milliseconds since the epoch. The watch's
/// own clock, which is the phone's: the two are kept in step by the pairing.
const String watchAtKey = 'at';

/// `{"type": "command", "command": "start"}`: a button on the wrist.
const String watchCommandType = 'command';

/// Which button it was, one of the four below.
const String watchCommandKey = 'command';

/// Start a ride.
const String watchCommandStart = 'start';

/// Suspend the ride.
const String watchCommandPause = 'pause';

/// Carry on.
const String watchCommandResume = 'resume';

/// Finish the ride. The phone cannot save it without the rider — the ride is
/// named on a sheet — so this stops the recording and leaves it waiting.
const String watchCommandStop = 'stop';

/// `{"type": "heartRateStopped"}`: the rider ended the watch's workout session
/// to save its battery. The ride goes on without a heart rate.
const String watchHeartRateStoppedType = 'heartRateStopped';

// --------------------------------------------------------- phone → watch

/// `{"type": "workout", "action": "start"}`: asks the watch to begin or end
/// its workout session, so the rider does not have to touch the wrist at all.
const String watchWorkoutType = 'workout';

/// Which of the two, [watchWorkoutStart] or [watchWorkoutStop].
const String watchWorkoutActionKey = 'action';

/// Begin measuring.
const String watchWorkoutStart = 'start';

/// Stop measuring.
const String watchWorkoutStop = 'stop';

/// `{"type": "context", "status": ..., ...}`: the application context once
/// more, as a message. Wear OS only: the Data Layer holds a data item that is
/// not marked urgent back for up to half an hour, and the plugin does not
/// mark it, so the phone sends every context this way too. The data item
/// stays the one a watch app opened mid-ride reads. The Apple app ignores
/// it, and the iPhone never sends it.
const String watchContextType = 'context';

// ------------------------------------------------- phone → watch context

/// What the ride is doing: [watchStatusIdle], [watchStatusActive] or
/// [watchStatusPaused].
const String watchStatusKey = 'status';

/// No ride is being recorded.
const String watchStatusIdle = 'idle';

/// A ride is running.
const String watchStatusActive = 'active';

/// A ride is suspended, by the rider or by auto-pause.
const String watchStatusPaused = 'paused';

/// The distance ridden, formatted: `3.2 km`.
const String watchDistanceKey = 'distance';

/// The time ridden, formatted: `00:42`.
const String watchElapsedKey = 'elapsed';

/// The current speed, formatted: `18.0 km/h`.
const String watchSpeedKey = 'speed';

/// The SF Symbol for the next turn, or an empty string without guidance. The
/// Wear OS app draws its own icon for each of them.
const String watchTurnIconKey = 'turnIcon';

/// What that turn is called, translated: `Turn left`.
const String watchTurnLabelKey = 'turnLabel';

/// How far it is, formatted: `150 m`.
const String watchTurnDistanceKey = 'turnDistance';

/// Whether the rider has left the route, which decides the haptic.
const String watchOffRouteKey = 'offRoute';

/// The instant of the last cue the rider should feel, in milliseconds since
/// the epoch, or `0` while there has been none.
///
/// The context is a picture, not an event, so a haptic cannot be sent as one:
/// the watch plays it when this number *changes*, once, and a watch that was
/// asleep through three turns wakes up to one buzz rather than three.
const String watchCueKey = 'cue';

/// The app's accent colour as `#RRGGBB`, the dark-theme shade: the watch
/// screen is always dark. The watch tints its heart and buttons with it, so
/// the wrist matches the phone.
const String watchAccentKey = 'accent';

/// Whether the watch should end its workout while the ride is paused and
/// wait to be launched again, rather than pause the workout: the "Rest the
/// sensor while paused" switch. Off, a paused workout keeps the sensor at its
/// cadence but keeps the watch app awake for the resume; on, the sensor
/// rests and the phone wakes the app ([watchWorkoutStart] or HealthKit's
/// launch) the moment the ride goes on.
const String watchRestKey = 'rest';

/// How often the context goes out while a ride runs.
///
/// Every fix would be a wake-up a second for a screen the rider looks at
/// twice an hour. A change of [watchStatusKey] or of [watchCueKey] goes
/// straight out, because both are things the rider is waiting for.
const Duration watchContextThrottle = Duration(seconds: 5);
