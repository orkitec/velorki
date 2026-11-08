import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'watch_gateway.g.dart';

/// What the watch on [platform] is called, as a sensor. A brand name, so it
/// reads the same in every language.
String watchName(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 'Wear OS' : 'Apple Watch';

/// The link to the watch app, as the little of WatchConnectivity Velorki uses.
///
/// Everything the `watch_connectivity` package offers is behind this one
/// interface, so the tests never touch the plugin. Nothing here asks the
/// rider for anything: WatchConnectivity raises no prompt, and the watch app
/// only asks the OS on the *watch* for HealthKit, when the rider opens it.
abstract interface class WatchGateway {
  /// Whether this platform can talk to a watch at all.
  Future<bool> isSupported();

  /// Whether a watch is paired with this phone.
  Future<bool> isPaired();

  /// Whether the watch app is running and can be reached right now.
  Future<bool> isReachable();

  /// Everything the watch app sends, as it sends it. A broadcast stream: both
  /// the sensor source and the bridge listen to it.
  Stream<Map<String, Object?>> get messages;

  /// Sends one message. Dropped by the OS when the watch app is not
  /// reachable, which is what a message is for.
  Future<void> sendMessage(Map<String, Object?> message);

  /// Replaces the dictionary the watch app wakes up to. Only the latest one
  /// survives.
  Future<void> updateApplicationContext(Map<String, Object?> context);

  /// Launches the watch app into a cycling workout through HealthKit, for a
  /// watch whose app is not running and so cannot be sent a message. True
  /// when watchOS took the request. Always false on Android, where there is
  /// no such launch: a message reaches a Wear OS app that is not running
  /// through its listener service, so [isReachable] covers that case.
  Future<bool> launchWorkout();

  /// Posts a notification on the phone saying the watch has started a ride,
  /// for a phone whose app is in the background: iOS launches it there for
  /// the watch's message, and only the rider can bring it to the front.
  /// Does nothing while the app is on screen. True when one was posted.
  Future<bool> notifyRideStarted({required String title, required String body});
}

/// Whether [platform] has a watch Velorki can talk to: an Apple Watch on
/// iOS, a Wear OS watch on Android. A rider on any other platform never sees
/// the switch.
bool watchSupportedOn(TargetPlatform platform) =>
    platform == TargetPlatform.iOS || platform == TargetPlatform.android;

/// The watch link of this platform, or `null` where there is none — which
/// is the default, because WatchConnectivity comes through a package with
/// Google Play code in its Android half.
///
/// `main.dart` installs the real gateway over this (`watchGatewayOverride`)
/// and `main_fdroid.dart` does not, so the F-Droid build has no watch.
@Riverpod(keepAlive: true)
WatchGateway? watchGateway(Ref ref) => null;

/// Whether this phone has a watch to offer the rider at all: the platform can
/// talk to one, and one is paired.
///
/// Asked once, when Settings → Sensors is drawn; the switch is simply absent
/// while it has not answered or answered `false`.
@Riverpod(keepAlive: true)
Future<bool> watchPaired(Ref ref) async {
  final gateway = ref.watch(watchGatewayProvider);
  if (gateway == null) return false;
  if (!await gateway.isSupported()) return false;
  return gateway.isPaired();
}
