import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:live_activities/live_activities.dart';
import 'package:logging/logging.dart';

import 'live_activity.dart';

/// The ride's lock-screen card over the `live_activities` plugin.
///
/// Reached from an entry point and nowhere else — `main.dart` installs
/// [liveActivityOverride], `main_fdroid.dart` does not — so a build without
/// Google Play never compiles the plugin in. Android has no card either way.
final Logger _log = Logger('velorki.recording');

/// [rideLiveActivityProvider] with the real card behind it on iOS.
Override liveActivityOverride() => rideLiveActivityProvider.overrideWith((ref) {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return const NoRideLiveActivity();
  }
  final activity = PluginRideLiveActivity();
  ref.onDispose(() => activity.end());
  return activity;
});

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
