import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../recording/application/recording_controller.dart';
import '../data/ble_gateway.dart';
import '../data/ble_sensor_source.dart';
import '../data/paired_sensors.dart';
import '../data/sensor_settings.dart';
import 'sensor_hub.dart';

part 'ble_sources_controller.g.dart';

final Logger _log = Logger('velorki.sensors.ble');

/// Where a paired device stands, as the Bluetooth sensors screen shows it.
enum BleLinkStatus {
  /// Nothing is connected to it, and nothing is trying to be.
  off,

  /// It is being connected to, or was dropped and is being come back for.
  connecting,

  /// It is connected and reporting.
  connected,
}

/// Whether a screen is asking for the paired sensors to be connected right
/// now.
///
/// Claimed by the Bluetooth sensors screen for as long as it is open, which is
/// the only way a rider sees a live reading without recording a ride. Counted
/// rather than switched, so a screen pushed over another one does not
/// disconnect the radio on its way back.
///
/// A [ChangeNotifier] rather than a provider's own state: the claim is made
/// and given back from a widget's `initState` and `dispose`, and Riverpod does
/// not allow a provider to be written from either.
class BleLiveClaims extends ChangeNotifier {
  int _holds = 0;

  /// Whether anything is asking.
  bool get isLive => _holds > 0;

  /// Asks for the paired sensors to be connected.
  void acquire() {
    _holds++;
    if (_holds == 1) notifyListeners();
  }

  /// Gives that claim back.
  void release() {
    if (_holds == 0) return;
    _holds--;
    if (_holds == 0) notifyListeners();
  }
}

/// The claims on a live connection.
@Riverpod(keepAlive: true)
BleLiveClaims bleLive(Ref ref) {
  final claims = BleLiveClaims();
  ref.onDispose(claims.dispose);
  return claims;
}

/// Connects the paired Bluetooth devices and registers them with the hub,
/// while there is any reason to.
///
/// There are exactly two reasons: a ride is recording, or the Bluetooth
/// sensors screen is open. Outside them every device is disconnected and
/// unregistered, because a radio kept open for a number nobody is looking at
/// is battery spent for nothing — and with nothing paired at all this never
/// touches the plugin, which is what makes the whole feature optional. The
/// battery saver changes none of it: a sensor sends what it sends, and
/// listening less often would not make it send less.
///
/// Kept alive and read once in `bootstrap()`, exactly like the other sensor
/// controllers: a provider nobody reads is one that never exists, and then it
/// observes nothing.
@Riverpod(keepAlive: true)
class BleSources extends _$BleSources {
  final Map<String, BleSensorSource> _sources = <String, BleSensorSource>{};

  /// The work queued so far, so that two transitions in quick succession are
  /// applied in order rather than racing each other. Tests await it.
  Future<void> _pending = Future<void>.value();

  bool _disposed = false;

  @override
  Map<String, BleLinkStatus> build() {
    ref.listen(pairedSensorsProvider, (previous, next) => _schedule());
    ref.listen(recordingControllerProvider, (previous, next) => _schedule());
    final live = ref.read(bleLiveProvider)..addListener(_schedule);
    ref.onDispose(() => live.removeListener(_schedule));
    ref.onDispose(_shutdown);
    _schedule();
    return const <String, BleLinkStatus>{};
  }

  /// Resolves once everything asked for so far has been applied. Only the
  /// tests need this; the app is happy to let it run.
  Future<void> get settled => _pending;

  /// Where the device with [deviceId] stands.
  BleLinkStatus statusOf(String deviceId) =>
      state[deviceId] ?? BleLinkStatus.off;

  void _schedule() {
    _pending = _pending
        .then((_) => _sync())
        .catchError(
          (Object error, StackTrace stackTrace) =>
              _log.warning('ble sources failed', error, stackTrace),
        );
  }

  Future<void> _sync() async {
    if (_disposed) return;
    final gateway = ref.read(bleGatewayProvider);
    final paired = ref.read(pairedSensorsProvider);
    final wanted =
        gateway != null &&
        paired.isNotEmpty &&
        (ref.read(recordingControllerProvider).isRecording ||
            ref.read(bleLiveProvider).isLive);
    final devices = <String, PairedSensor>{
      if (wanted)
        for (final device in paired) device.id: device,
    };

    for (final id in _sources.keys.toList(growable: false)) {
      // A device that was renamed is the same device and is left connected;
      // one whose kinds changed is a different source, because the kinds
      // decide which characteristics it subscribes to.
      final device = devices[id];
      if (device != null && setEquals(device.kinds, _sources[id]!.kinds)) {
        continue;
      }
      final source = _sources.remove(id)!;
      ref.read(sensorHubProvider.notifier).unregister(source.id);
      await source.dispose();
    }
    _publish();

    for (final device in devices.values) {
      if (_disposed || _sources.containsKey(device.id)) continue;
      final source = BleSensorSource(
        gateway: gateway!,
        device: device,
        wheelCircumferenceM: () =>
            ref.read(sensorSettingsProvider).wheelCircumferenceM,
        onLinkChanged: _publish,
      );
      _sources[device.id] = source;
      ref.read(sensorHubProvider.notifier).register(source);
      _publish();
      await source.start();
    }
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    state = Map<String, BleLinkStatus>.unmodifiable(<String, BleLinkStatus>{
      for (final entry in _sources.entries)
        entry.key: entry.value.isConnected
            ? BleLinkStatus.connected
            : BleLinkStatus.connecting,
    });
  }

  /// The container is going: every device is let go of. Nothing is
  /// unregistered, because the hub is on its way out too and `ref` may not be
  /// read from here.
  void _shutdown() {
    _disposed = true;
    for (final source in _sources.values) {
      unawaited(source.dispose());
    }
    _sources.clear();
  }
}
