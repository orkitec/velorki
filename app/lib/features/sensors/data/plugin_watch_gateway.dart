import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:logging/logging.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import 'watch_gateway.dart';

/// The link to the Apple Watch over the `watch_connectivity` package.
///
/// Reached from an entry point and nowhere else — `main.dart` installs
/// [watchGatewayOverride], `main_fdroid.dart` does not — so a build without
/// Google Play never compiles the package in. On Android the gateway is
/// null in both builds anyway.
final Logger _log = Logger('velorki.sensors.watch');

/// [watchGatewayProvider] with the plugin behind it, where the platform has
/// a watch Velorki can talk to.
///
/// Constructing it asks the OS for nothing and wakes no watch; the gateway
/// only reaches the plugin once something calls it, and the only thing that
/// calls it is the Apple Watch switch in Settings → Sensors and the bridge
/// behind it.
Override watchGatewayOverride() => watchGatewayProvider.overrideWith(
  (ref) =>
      watchSupportedOn(defaultTargetPlatform) ? PluginWatchGateway() : null,
);

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
