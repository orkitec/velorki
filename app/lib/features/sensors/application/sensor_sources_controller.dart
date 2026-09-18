import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../recording/application/recording_controller.dart';
import '../../recording/data/battery_saver.dart';
import '../data/health_gateway.dart';
import '../data/health_sensor_source.dart';
import '../data/sensor_settings.dart';
import 'sensor_hub.dart';

part 'sensor_sources_controller.g.dart';

/// Registers and unregisters the platform sources as the rider's settings and
/// the recorder change.
///
/// The health source exists only while both are true: Health is switched on in
/// Settings, and a ride is being recorded. Polling a health store between
/// rides would cost battery for a number nobody is looking at, and polling it
/// with the switch off would be reading data the rider never offered.
///
/// Kept alive and read once in `bootstrap()`, exactly like the other always-on
/// providers: one nobody reads is one that never exists, and then it observes
/// nothing.
@Riverpod(keepAlive: true)
class SensorSources extends _$SensorSources {
  HealthSensorSource? _health;

  /// The work queued so far, so that two transitions in quick succession are
  /// applied in order rather than racing each other. Tests await it.
  Future<void> _pending = Future<void>.value();

  @override
  void build() {
    ref.listen(sensorSettingsProvider, (previous, next) => _schedule());
    ref.listen(recordingControllerProvider, (previous, next) => _schedule());
    ref.onDispose(_disposeSource);
    _schedule();
  }

  /// Resolves once everything the settings and the recorder have asked for has
  /// been applied. Only the tests need this; the app is happy to let it run.
  Future<void> get settled => _pending;

  void _schedule() {
    _pending = _pending.then((_) => _sync()).catchError((Object _) {});
  }

  Future<void> _sync() async {
    final gateway = ref.read(healthGatewayProvider);
    final wanted =
        gateway != null &&
        ref.read(sensorSettingsProvider).health &&
        ref.read(recordingControllerProvider).isRecording;
    if (wanted == (_health != null)) return;

    if (wanted) {
      final source = HealthSensorSource(
        gateway: gateway,
        interval: _pollInterval,
      );
      _health = source;
      ref.read(sensorHubProvider.notifier).register(source);
      await source.start();
      return;
    }

    final source = _health!;
    _health = null;
    ref.read(sensorHubProvider.notifier).unregister(source.id);
    await source.dispose();
  }

  /// The poll follows the ride's battery saver, which is also what the GPS
  /// profile and the screen do.
  Duration _pollInterval() => ref.read(batterySaverActiveProvider)
      ? healthPollSaverInterval
      : healthPollInterval;

  void _disposeSource() {
    final source = _health;
    _health = null;
    if (source != null) unawaited(source.dispose());
  }
}
