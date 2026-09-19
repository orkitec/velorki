import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

part 'watch_gateway.g.dart';

final Logger _log = Logger('velorki.sensors.watch');

/// What the watch is called in the interface. A brand name, so it reads the
/// same in every language.
const String watchName = 'Apple Watch';

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
  /// when watchOS took the request.
  Future<bool> launchWorkout();

  /// Posts a notification on the phone saying the watch has started a ride,
  /// for a phone whose app is in the background: iOS launches it there for
  /// the watch's message, and only the rider can bring it to the front.
  /// Does nothing while the app is on screen. True when one was posted.
  Future<bool> notifyRideStarted({required String title, required String body});
}

/// Whether [platform] has a watch Velorki can talk to.
///
/// iOS only: the phone side of this feature is an Apple Watch companion app,
/// and a rider on any other platform never sees the switch.
bool watchSupportedOn(TargetPlatform platform) =>
    platform == TargetPlatform.iOS;

/// [WatchGateway] over the `watch_connectivity` package.
///
/// Every call is wrapped: a phone with no watch, or a plugin that is not
/// there, answers "no" instead of throwing into a recording.
class PluginWatchGateway implements WatchGateway {
  /// Creates a gateway. [watch] is only injected by this package's own tests.
  PluginWatchGateway({WatchConnectivity? watch})
    : _watch = watch ?? WatchConnectivity();

  final WatchConnectivity _watch;

  /// Mirrored in `ios/Runner/AppDelegate.swift`.
  static const MethodChannel _channel = MethodChannel('velorki/watch');

  @override
  Future<bool> launchWorkout() async {
    try {
      return await _channel.invokeMethod<bool>('launchWorkout') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> notifyRideStarted({
    required String title,
    required String body,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('notifyRideStarted', {
            'title': title,
            'body': body,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Android: the foreground service's own notification is already up.
      return false;
    }
  }

  @override
  Future<bool> isSupported() =>
      _guard('isSupported', false, () => _watch.isSupported);

  @override
  Future<bool> isPaired() => _guard('isPaired', false, () => _watch.isPaired);

  @override
  Future<bool> isReachable() =>
      _guard('isReachable', false, () => _watch.isReachable);

  @override
  Stream<Map<String, Object?>> get messages => _watch.messageStream
      .handleError(
        (Object error, StackTrace stackTrace) =>
            _log.warning('watch message stream failed', error, stackTrace),
      )
      .map(Map<String, Object?>.from);

  @override
  Future<void> sendMessage(Map<String, Object?> message) => _guard(
    'sendMessage',
    null,
    () => _watch.sendMessage(Map<String, dynamic>.from(message)),
  );

  @override
  Future<void> updateApplicationContext(Map<String, Object?> context) => _guard(
    'updateApplicationContext',
    null,
    () => _watch.updateApplicationContext(Map<String, dynamic>.from(context)),
  );

  Future<T> _guard<T>(
    String what,
    T fallback,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on Object catch (error, stackTrace) {
      _log.warning('watch $what failed', error, stackTrace);
      return fallback;
    }
  }
}

/// The watch link of this platform, or `null` where there is none.
///
/// Constructing it asks the OS for nothing and wakes no watch; the gateway
/// only reaches the plugin once something calls it, and the only thing that
/// calls it is the Apple Watch switch in Settings → Sensors and the bridge
/// behind it.
@Riverpod(keepAlive: true)
WatchGateway? watchGateway(Ref ref) =>
    watchSupportedOn(defaultTargetPlatform) ? PluginWatchGateway() : null;

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
