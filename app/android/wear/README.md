# Wear OS app

The Wear OS companion: the ride's figures on the wrist, the heart rate from
the watch's own sensor, and the buttons that drive the phone. The same app as
the Apple Watch one (`ios/VelorkiWatch/README.md`), rule for rule; read that
first, this only says where Wear OS differs.

A Gradle module of the Flutter Android project, Kotlin and Compose for Wear OS
(Material 3), minSdk 30 (Wear OS 3), applicationId `com.orkitec.velorki` as
Play requires for a companion, `com.google.android.wearable.standalone` false.
`settings.gradle.kts` includes it only when a `:wear:` task is asked for (or
with `-PvelorkiWear=true`, for an IDE sync): `flutter build` runs unqualified
tasks such as `bundleRelease`, which would build it beside the phone's, and
the F-Droid build never sees it.

```sh
cd app && flutter build apk --debug ...   # once: writes gradlew and local.properties
cd android
./gradlew :wear:testDebugUnitTest          # the JVM tests
./gradlew :wear:assembleDebug              # build/wear/outputs/apk/debug/
./gradlew :wear:bundleRelease              # build/wear/outputs/bundle/release/
```

**Version code**: 100000 + the pubspec's build number N (or
`-PvelorkiBuildNumber`), the name is the pubspec's. Play wants every code of
the app distinct; the phone's are N and the F-Droid build's per-ABI ones 1000,
2000 or 4000 + N, all under 100000 while N stays under 96000, which the build
checks. `release.yml` builds it with the phone's key in the same job and
approval as the phone's, after the phone's upload, and uploads it to the Wear
OS internal track (`wear:qa`) only while the repository variable
`WEAR_RELEASE` is `true`. Unset, the run says so in a notice: add the Wear OS
form factor in the Play Console (Test and release → Advanced settings → Form
factors) first, then set the variable.

## The parts

- `WatchProtocol.kt`: the keys and message shapes, and the
  `watch_connectivity` plugin's wire format: a Java-serialised `HashMap`,
  messages on the path `watch_connectivity` to every connected node, the
  context as the data item `/watch_connectivity`. Only plain values are
  deserialised.
- `RideSession.kt`: `RideSession.swift`'s rules over interfaces, so the JVM
  tests run them: measure while the phone rides, pause with it, end at a pause
  with "Rest the sensor", a command resent every 2 s up to 8 times until the
  phone's context shows it done, one haptic per cue.
- `ExerciseMonitor.kt`: the heart rate through Health Services, a `BIKING`
  exercise with heart rate only (no GPS, no auto-pause), which keeps the
  sensor measuring with the wrist down. Nothing goes to Health Connect from
  the watch; the phone writes the ride. An exercise left running by a process
  that died is carried on.
- `DataLayer.kt`: sending, the last context for an app opened mid-ride, and
  `PhoneListenerService`, which the Data Layer wakes for a message or a new
  context even when the app is not running. This is Wear OS's stand-in for
  HealthKit's `startWatchApp`: the phone's `launchWorkout` answers false on
  Android and the `workout` message does the waking.
- `RideService.kt`: the foreground service (type `health`) and the Ongoing
  Activity that keeps the ride on the watch face while a ride runs or the
  sensor measures.
- `RideScreen.kt`: the screen. Heart rate, speed, distance and time two by
  two with the unit after the last space set small, the next turn (the
  phone's SF Symbol name drawn as the phone's own Material icon), Pause or
  Resume and Finish on the bottom edge, the title Riding, Paused or Velorki
  beside the clock. A second page below (swipe or crown) holds Stop or Start
  heart rate and the footnotes. Text scales with the screen and shrinks to
  half before it is cut; the buttons never shrink.

The context also arrives as a `context` message (`watch_protocol.dart`,
`watchContextType`): Wear OS holds back a data item not marked urgent for up
to half an hour, and the plugin does not mark it.

## Language

Its own words are `src/main/res/values*/strings.xml`, in every app language
(English the default), in the terms of `docs/GLOSSARY.md`. Everything else is
formatted and translated by the phone.

## Testing it

- `src/test`: `WatchProtocolTest` decodes and encodes every message in
  `test/fixtures/watch/messages.json` through the plugin's wire format, the
  same file `watch_ride_bridge_test.dart` holds the phone to;
  `RideSessionTest` the session's rules.
- Debug builds only (`src/debug`): `DebugFeedReceiver` plays the phone from
  adb, because pairing an emulator needs a Play Store phone image, an account
  and the companion app. What the app sends is in logcat under `VelorkiWatch`.

  ```sh
  adb -s <watch> shell am broadcast -a com.orkitec.velorki.wear.debug.FEED \
    -p com.orkitec.velorki --es b64 "$(printf '%s' "$json" | base64)"
  ```

  A JSON object with a `type` is a message, one without is the context.
- A live heart rate on the emulator from Health Services' synthetic data:

  ```sh
  adb -s <watch> shell am broadcast -a whs.USE_SYNTHETIC_PROVIDERS com.google.android.wearable.healthservices
  adb -s <watch> shell am broadcast -a whs.synthetic.user.START_BIKING com.google.android.wearable.healthservices
  ```

- End to end needs a paired phone: the release (or a debug) build on a watch
  paired through the Wear OS or Galaxy Wearable app with a phone running a
  Play build of the phone app, both signed with the same key, and the watch
  switch on in Settings → Sensors.

## Not done

- Starting a ride from the wrist while the phone's app is not running: the
  plugin listens only while Flutter's engine is up, and Android does not let
  an app in the background start the recorder's location service. The wrist
  says the phone did not answer, as on the Apple Watch.
- Complications, tiles, and an ambient (always-on) treatment.
