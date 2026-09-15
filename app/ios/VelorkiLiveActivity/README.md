# VelorkiLiveActivity

The lock-screen card and Dynamic Island of a running ride.

The target `VelorkiLiveActivity` is a widget extension in `Runner.xcodeproj`,
embedded in Runner, deployment target 16.2, built from the three Swift files
and the `Info.plist` here. Runner and the extension both carry the App Group
`group.com.orkitec.velorki` in their entitlements files; the same string is
`liveActivityAppGroupId` in `lib/features/recording/data/live_activity.dart`,
change one and change the other. Push Notifications are not needed: the
activity is created with `iOSEnableRemoteUpdates: false` and every figure
comes from the phone itself.

The Dart side calls the plugin from
`lib/features/recording/data/live_activity.dart`; without the extension every
call fails quietly.

Flutter's "Thin Binary" script phase must run after "Embed Foundation
Extensions" in the Runner target, or Xcode reports a build cycle.

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
