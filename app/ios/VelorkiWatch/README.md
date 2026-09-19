# VelorkiWatch

The Apple Watch companion: the ride's figures on the wrist, the heart rate
from the watch's own sensor, and four buttons that drive the phone.

The target `VelorkiWatch` is a watchOS app in `Runner.xcodeproj`, embedded in
Runner by the "Embed Watch Content" phase (into `$(CONTENTS_FOLDER_PATH)/Watch`,
placed before Flutter's "Thin Binary" phase, or Xcode reports a build cycle).
A modern single-target watch app — no separate WatchKit extension —
deployment target watchOS 10.0, bundle id `com.orkitec.velorki.watchkitapp`,
built from the three Swift files here. It never runs on its own
(`WKRunsIndependentlyOfCompanionApp` is false): without the phone it has
nothing to show and nowhere to send what it measures.

The watch is a display and a sensor, never a second recorder. The phone's
recorder does the work, writes the track and saves the ride; this app sends
readings and commands and draws what the phone reports back.

Nothing here runs until the rider switches "Apple Watch" on in the phone's
Settings → Sensors. The one prompt the watch itself raises is HealthKit's, the
first time a workout is started from this app.

## Battery

A watch app can save very little on its own, so there is one thing it offers:
**Stop heart rate** ends the workout session — and with it the sensor — while
the ride goes on on the phone. Anything more belongs to watchOS Low Power
Mode, which the screen mentions once in a footnote and does not try to
duplicate.

The workout session is what keeps the heart rate sensor measuring with the
wrist down; `UIBackgroundModes` is `workout-processing` for the same reason.
The workout itself is **discarded** when it ends: the phone writes the ride to
Health with the distance and the track it recorded, and a second workout from
here would be the same ride twice in the rider's day.

## The messages

The other half of this is Dart, in
`lib/features/sensors/data/watch_protocol.dart`, which spells out the same
keys. Change one and change the other.

Watch → phone, `WCSession.sendMessage`:

```
{"type": "heartRate", "bpm": 142, "at": <ms since epoch>}   about once a second
{"type": "command", "command": "start"|"pause"|"resume"|"stop"}
{"type": "heartRateStopped"}                                 measuring is over
```

`stop` does not save the ride: it is named on a sheet on the phone. The phone
stops recording and opens that sheet the next time the rider looks at it.

Phone → watch, `sendMessage`:

```
{"type": "workout", "action": "start"|"stop"}
```

The phone asks for the workout when a ride starts and the watch app is
reachable, so the rider need not touch the wrist at all; tapping Start here
does the same thing from this end.

Phone → watch, `updateApplicationContext` — one dictionary, latest wins, sent
on every change and at most every 5 s while a ride runs:

```
{"status": "idle"|"active"|"paused",
 "distance": "3.2 km", "elapsed": "00:42", "speed": "18.0 km/h",
 "turnIcon": "arrow.turn.up.left", "turnLabel": "Turn left",
 "turnDistance": "150 m", "offRoute": false,
 "cue": <ms since epoch, 0 for none>}
```

Every string is formatted and translated by the phone, which knows the rider's
units and language; this app knows neither, and its own handful of words are
English. `cue` is a timestamp that changes when the rider should *feel*
something — the cue for the corner they are at, or the news that they have
left the route. The watch plays one haptic per change, `.failure` while
`offRoute` is true and `.notification` otherwise, so a watch that slept
through three turns buzzes once rather than three times.

## Testing it

- Xcode → Window → Devices and Simulators → Simulators: an iPhone simulator
  and a watch simulator paired to it. `flutter run -d <iphone simulator>`
  builds and installs both; the watch app has to be opened by hand on the
  watch simulator.
- Building the scheme needs the watchOS *simulator runtime* matching the
  installed watchOS SDK. Without it Xcode fails with "This scheme builds an
  embedded Apple Watch app. watchOS N must be installed in order to run the
  scheme"; `xcodebuild -downloadPlatform watchOS` installs it.
- Switch Settings → Sensors → Apple Watch on in the app on the phone
  simulator. The switch only appears when a watch is paired.
- A simulated watch has no heart rate sensor: the workout session starts and
  reports nothing. The figures, the buttons, the turn row and the haptics can
  all be driven from the simulator; the heart rate needs a real watch.
- `integration_test/live_watch_test.dart` drives the whole loop on the iOS
  simulator with a fake watch behind `watchGatewayProvider`, which is what CI
  runs — no watch simulator involved.

## Not done

- **The app icon.** There is no asset catalog here yet, so the watch app shows
  the system placeholder. It needs an `AppIcon` set (and
  `ASSETCATALOG_COMPILER_APPICON_NAME`) before the app can be submitted.
- **Complications** and any Always-On display treatment.
- **Translation.** The figures arrive translated; the buttons and the two
  footnotes here are English.

The icon is `Assets.xcassets/AppIcon.appiconset/icon.png`, the app's own 1024 px
icon; watchOS masks it to a circle.
