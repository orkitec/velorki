import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

/// The App Group both the app and the widget extension are members of.
///
/// The plugin hands the activity's data over through the shared
/// `UserDefaults` of this group, so the same string has to be set as an App
/// Group capability on the `Runner` and the `VelorkiLiveActivity` targets in
/// Xcode. See `ios/VelorkiLiveActivity/README.md`.
const String liveActivityAppGroupId = 'group.com.orkitec.velorki';

/// Id of the ride activity. One ride, one activity, so a fixed string is
/// enough — and a fixed one also means a second start cannot leave an orphan
/// behind on the lock screen.
const String rideActivityId = 'velorki-ride';

/// The lock-screen card of a running ride.
///
/// Only iOS has one; everywhere else this is a no-op, which is what lets the
/// updater above it run the same code on both platforms.
abstract interface class RideLiveActivity {
  /// Puts the card on the lock screen with [data]. Does nothing when one is
  /// already up.
  Future<void> start(Map<String, Object?> data);

  /// Redraws the card with [data]. Does nothing when none is up.
  Future<void> update(Map<String, Object?> data);

  /// Takes the card away.
  Future<void> end();
}

/// A [RideLiveActivity] that does nothing: Android, the desktop builds, and
/// an iPhone too old for ActivityKit.
class NoRideLiveActivity implements RideLiveActivity {
  /// Creates the no-op.
  const NoRideLiveActivity();

  @override
  Future<void> start(Map<String, Object?> data) async {}

  @override
  Future<void> update(Map<String, Object?> data) async {}

  @override
  Future<void> end() async {}
}

/// The lock-screen card of the running app: nothing, until an entry point
/// installs the real one over it.
///
/// `live_activities` is an iOS plugin whose Android half pulls Google Play
/// libraries in, so `main.dart` installs [PluginRideLiveActivity] through
/// `liveActivityOverride` and `main_fdroid.dart` leaves it out. Android has
/// no card in either build.
final rideLiveActivityProvider = Provider<RideLiveActivity>(
  (ref) => const NoRideLiveActivity(),
);

/// The SF Symbol the widget extension draws for [kind].
///
/// Symbol names rather than an icon font because the card is rendered by
/// SwiftUI, which knows nothing of the app's Material icons. Chosen from the
/// set that exists since iOS 16, so the extension never draws a blank.
String turnSymbol(TurnKind kind) => switch (kind) {
  TurnKind.left || TurnKind.sharpLeft => 'arrow.turn.up.left',
  TurnKind.right || TurnKind.sharpRight => 'arrow.turn.up.right',
  TurnKind.slightLeft ||
  TurnKind.keepLeft ||
  TurnKind.exitLeft => 'arrow.up.left',
  TurnKind.slightRight ||
  TurnKind.keepRight ||
  TurnKind.exitRight => 'arrow.up.right',
  TurnKind.uTurn || TurnKind.uTurnLeft => 'arrow.uturn.left',
  TurnKind.uTurnRight => 'arrow.uturn.right',
  // SF Symbols has no mirrored roundabout, so both turn the same way.
  TurnKind.roundabout ||
  TurnKind.roundaboutLeft => 'arrow.triangle.turn.up.right.circle',
  TurnKind.end => 'flag.checkered',
  TurnKind.straight || TurnKind.beeline || TurnKind.offRoad => 'arrow.up',
};

/// The symbol for a rider who has left the route.
const String offRouteSymbol = 'exclamationmark.triangle';
