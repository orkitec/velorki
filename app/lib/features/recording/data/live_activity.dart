import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_activities/live_activities.dart';
import 'package:logging/logging.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

/// The App Group both the app and the widget extension are members of.
///
/// The plugin hands the activity's data over through the shared
/// `UserDefaults` of this group, so the same string has to be set as an App
/// Group capability on the `Runner` and the `VelorkiLiveActivity` targets in
/// Xcode. See `ios/VelorkiLiveActivity/README.md`.
final Logger _log = Logger('velorki.recording');

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

/// The real card, over the `live_activities` plugin.
///
/// Every call is wrapped: a debug build without the widget extension, an
/// iPhone whose owner switched live activities off, an iOS below 16.1 — all of
/// them fail here, and none of them is worth interrupting a ride for.
class PluginRideLiveActivity implements RideLiveActivity {
  /// Creates the activity.
  PluginRideLiveActivity({LiveActivities? plugin})
    : _plugin = plugin ?? LiveActivities();

  final LiveActivities _plugin;

  /// Whether the app group was handed to the plugin already.
  bool _initialized = false;

  /// ActivityKit's id for the card that is up, as `createActivity` handed it
  /// back; `null` while there is none. The plugin finds an activity by this
  /// id, not by the name it was requested under: updates and the end sent
  /// under the name went to "Activity not found", and the card sat at its
  /// first figures for the whole ride.
  String? _activityId;

  bool get _running => _activityId != null;

  @override
  Future<void> start(Map<String, Object?> data) async {
    if (_running) return;
    await _quietly(() async {
      if (!_initialized) {
        // `requestAndroidNotificationPermission` would pop the Android
        // permission dialog; this implementation is only ever built on iOS,
        // but there is no reason to leave that trap armed.
        await _plugin.init(
          appGroupId: liveActivityAppGroupId,
          requestAndroidNotificationPermission: false,
        );
        _initialized = true;
      }
      if (!await _plugin.areActivitiesSupported()) return;
      _activityId = await _plugin.createActivity(
        rideActivityId,
        Map<String, dynamic>.of(data),
        // Remote updates would need the Push Notifications capability, and
        // every figure on the card comes from this phone anyway.
        iOSEnableRemoteUpdates: false,
        removeWhenAppIsKilled: true,
      );
      if (_activityId == null) _log.warning('Live activity: no id came back');
    });
  }

  @override
  Future<void> update(Map<String, Object?> data) async {
    final id = _activityId;
    if (id == null) return;
    await _quietly(
      () => _plugin.updateActivity(id, Map<String, dynamic>.of(data)),
    );
  }

  @override
  Future<void> end() async {
    final id = _activityId;
    if (id == null) return;
    _activityId = null;
    await _quietly(() => _plugin.endActivity(id));
  }

  /// Nothing here may take the ride down, but nothing may vanish either: a
  /// card that silently stops updating is what this looked like once.
  Future<void> _quietly(Future<void> Function() call) async {
    try {
      await call();
    } catch (error, stackTrace) {
      _log.warning('Live activity call failed', error, stackTrace);
    }
  }
}

/// The lock-screen card of the running app: the real one on iOS, nothing
/// anywhere else.
final rideLiveActivityProvider = Provider<RideLiveActivity>((ref) {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return const NoRideLiveActivity();
  }
  final activity = PluginRideLiveActivity();
  ref.onDispose(() => activity.end());
  return activity;
});

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
