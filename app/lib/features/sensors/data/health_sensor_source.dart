import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/sensor_reading.dart';
import '../domain/sensor_source.dart';
import 'health_gateway.dart';

/// The id [HealthSensorSource] registers itself with.
const String healthSensorSourceId = 'health';

/// How often the health store is asked for new samples while a ride records.
const Duration healthPollInterval = Duration(seconds: 5);

/// The same, in battery saver. A watch writes a sample every few seconds
/// either way; six times fewer queries is six times fewer wake-ups.
const Duration healthPollSaverInterval = Duration(seconds: 30);

/// How far back the first poll of a ride looks.
///
/// Long enough that a watch which was already measuring when the ride started
/// contributes its last reading, short enough that nothing from before the
/// ride is stamped onto it.
const Duration healthFirstPollWindow = Duration(seconds: 60);

/// Heart rate out of the platform's health store.
///
/// A poll rather than a stream, because neither HealthKit nor Health Connect
/// pushes: every [healthPollInterval] the store is asked what it has learned
/// since the last sample seen, and each new sample becomes one reading. That
/// makes this the slowest and least live of the sources, which is exactly what
/// [healthSensorPriority] says — a real strap takes over the moment it reports.
class HealthSensorSource implements SensorSource {
  /// Creates the source.
  ///
  /// [interval] is asked before every wait rather than fixed, so the battery
  /// saver can stretch the poll mid-ride.
  HealthSensorSource({
    required this.gateway,
    required this.interval,
    DateTime Function()? clock,
    TargetPlatform? platform,
  }) : _clock = clock ?? DateTime.now,
       name = healthStoreName(platform ?? defaultTargetPlatform);

  /// The health store the samples come from.
  final HealthGateway gateway;

  /// How long to wait before the next poll, asked again every time.
  final Duration Function() interval;

  final DateTime Function() _clock;

  final StreamController<SensorReading> _readings =
      StreamController<SensorReading>.broadcast();

  Timer? _timer;
  bool _running = false;

  /// The start of the next query: the newest sample seen so far.
  DateTime _since = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// The timestamps already emitted at exactly [_since]. The next query starts
  /// at [_since] inclusive, so those are the only samples that can come back
  /// twice, and this is all the dedupe that is needed.
  Set<DateTime> _seen = <DateTime>{};

  @override
  String get id => healthSensorSourceId;

  @override
  final String name;

  @override
  Set<SensorKind> get kinds => const <SensorKind>{SensorKind.heartRate};

  @override
  int get priority => healthSensorPriority;

  @override
  Stream<SensorReading> get readings => _readings.stream;

  /// Whether the poll is running.
  bool get isPolling => _running;

  /// Starts polling. The first query covers the last [healthFirstPollWindow].
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _since = _clock().toUtc().subtract(healthFirstPollWindow);
    _seen = <DateTime>{};
    await poll();
    _schedule();
  }

  /// Stops polling. The stream stays open, so a source that is started again
  /// keeps its subscribers.
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Stops polling and closes the stream; the source cannot be started again.
  Future<void> dispose() async {
    await stop();
    await _readings.close();
  }

  /// Asks the store for everything since the last sample seen and emits what
  /// is new, oldest first.
  ///
  /// Public so a test can drive the poll without waiting out the timer; the
  /// app only ever gets here through [start].
  Future<void> poll() async {
    final now = _clock().toUtc();
    if (!now.isAfter(_since)) return;
    final samples = await gateway.heartRate(_since, now);
    if (_readings.isClosed) return;
    final ordered = <HeartRateSample>[...samples]
      ..sort((a, b) => a.at.compareTo(b.at));

    DateTime? newest;
    for (final sample in ordered) {
      final at = sample.at.toUtc();
      if (at.isBefore(_since) || _seen.contains(at)) continue;
      _readings.add(
        SensorReading(
          kind: SensorKind.heartRate,
          value: sample.bpm.toDouble(),
          at: at,
          sourceId: id,
        ),
      );
      if (newest == null || at.isAfter(newest)) newest = at;
    }
    if (newest == null) return;
    _since = newest;
    _seen = <DateTime>{newest};
  }

  void _schedule() {
    if (!_running) return;
    _timer = Timer(interval(), () async {
      if (!_running) return;
      await poll();
      _schedule();
    });
  }
}
