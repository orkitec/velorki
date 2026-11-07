import 'app/build_flavour.dart';
import 'app/startup.dart';
import 'core/plus/plus_gate.dart';

/// The entry point of the Google-free build, the one F-Droid publishes.
///
/// Velorki plans, records, navigates, speaks, reads Bluetooth sensors and
/// works offline from this entry point exactly as it does from `main.dart`:
/// all of that is the app's own code over OpenStreetMap data and free
/// plugins. What is missing is what only a closed-source library can do —
/// buying Plus, Google Drive sync, the store's rating dialog and update
/// notice, the Apple Watch link and the iOS lock-screen card — and it is
/// missing because this entry point installs no override for it, so
/// `pubspec.yaml` can drop those plugins entirely
/// (`tool/fdroid_strip.sh`).
///
/// Velorki Plus is left out of the interface altogether here, rather than
/// shown and refused: nobody can buy it in this build, so a Settings row, an
/// Ask button or a share link offering it would open a dead end — and a dead
/// end naming a paid add-on is what a store reads as an advertisement for
/// one. [plusOfferedProvider] is the one switch for all of it.
///
/// The Strava and Ride with GPS connections are left out of this build as
/// well, for now: `env/fdroid.json` carries no client id for either, which
/// is all it takes to leave both out of the interface. That is a decision
/// about the first submission rather than a technical one — the code is the
/// same here as in the store builds — and they may come back later. See
/// `docs/FDROID.md`.
Future<void> main() {
  googleServicesAvailable = false;
  return startVelorki(
    overrides: [plusOfferedProvider.overrideWithValue(false)],
  );
}
