# VelorkiLiveActivity

The lock-screen card and Dynamic Island of a running ride. The Swift here is
written but not wired up: a widget extension has to be a target in the Xcode
project, and the project file can only be edited on the Mac.

The Dart side is finished and already calls the plugin
(`lib/features/recording/data/live_activity.dart`); without this target every
call fails quietly and the app behaves as it does today.

## Adding the target

1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target… → Widget Extension**. Product name
   **`VelorkiLiveActivity`**, "Include Live Activity" ticked, "Include
   Configuration App Intent" unticked, "Embed in Application" = **Runner**.
   Finish, then **Activate** the scheme when asked.
3. Delete the files the template generated (`VelorkiLiveActivity.swift`,
   `VelorkiLiveActivityBundle.swift`, `VelorkiLiveActivityLiveActivity.swift`,
   `AppIntent.swift`, the asset catalog may stay) and add the four files from
   this directory to the target instead: `VelorkiLiveActivityBundle.swift`,
   `RideAttributes.swift`, `RideLiveActivityView.swift`, `Info.plist`. Point
   the target's **Info.plist File** build setting at this `Info.plist`.
4. Set the target's **iOS Deployment Target** to **16.2**.
5. **Signing & Capabilities → + Capability → App Groups** on *both* the
   `Runner` target and the `VelorkiLiveActivity` target, and tick
   `group.com.orkitec.velorki` in both. The same string is
   `liveActivityAppGroupId` in `lib/features/recording/data/live_activity.dart`;
   change one and change the other.
6. `NSSupportsLiveActivities` is already in `ios/Runner/Info.plist` and in the
   `Info.plist` here. Push Notifications are **not** needed: the activity is
   created with `iOSEnableRemoteUpdates: false` and every figure comes from the
   phone itself.

## How the data gets across

ActivityKit cannot diff a big content state, so the `live_activities` plugin
puts the figures in the App Group's `UserDefaults` under keys prefixed with the
activity's id, and only bumps `updateId` in the state. `RideState` reads them
back; the keys are exactly what `rideActivityData` writes in
`lib/features/recording/application/ride_notification_updater.dart`:
`distance`, `elapsed`, `speed`, `turnIcon`, `turnLabel`, `turnDistance`,
`paused`. Everything is formatted and translated on the Dart side, because the
app knows the rider's language and units and the extension does not.

`LiveActivitiesAppAttributes` must keep that name. The plugin requests the
activity with exactly this type; an extension that declares another one starts
an activity that never appears.

## Testing it on the iPhone

- Live Activities do not run in the simulator's lock screen in any useful way;
  use a real iPhone (a Dynamic Island needs a 14 Pro or newer, the lock-screen
  card works on any iPhone from 16.1).
- Settings → Face ID & Passcode → Live Activities has to be on.
- `flutter run --release -d <iphone>`, start a ride on the Record tab, lock the
  phone. The card should appear within a second or two and redraw every five
  seconds. Plan a route first and switch Settings → Navigation → turn-by-turn
  on to see the turn row.
- Stopping the ride removes the card. Force-quitting the app removes it too
  (`removeWhenAppIsKilled: true`).
- Nothing appears? Check the App Group is ticked on both targets and that the
  extension really is embedded in Runner (Runner → Build Phases → Embed
  Foundation Extensions).
