import 'dart:async';

import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/sensor_reading.dart';
import '../domain/sensor_snapshot.dart';
import '../domain/sensor_source.dart';

part 'sensor_hub.g.dart';

final Logger _log = Logger('velorki.sensors');

/// Every paired sensor, resolved into one reading per kind.
///
/// Sources register themselves here and the hub decides which of them a rider
/// actually sees: for each kind the reading of the highest-priority source that
/// has reported inside [sensorStaleness] wins, so a watch takes over from a
/// health store and hands back to it when it is put away. The recorder talks
/// to nothing else.
///
/// The resolution is redone at the moment of each incoming reading, against
/// that reading's own timestamp rather than a wall clock: a source that has
/// fallen silent cannot announce it, but the source that takes over from it
/// arrives with the very timestamp the decision has to be made at.
@Riverpod(keepAlive: true)
class SensorHub extends _$SensorHub {
  final Map<String, SensorSource> _sources = <String, SensorSource>{};
  final Map<String, StreamSubscription<SensorReading>> _subscriptions =
      <String, StreamSubscription<SensorReading>>{};

  /// The latest reading of every kind, per source.
  final Map<String, Map<SensorKind, SensorReading>> _latest =
      <String, Map<SensorKind, SensorReading>>{};

  @override
  SensorSnapshot build() {
    ref.onDispose(() {
      for (final subscription in _subscriptions.values) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
      _sources.clear();
      _latest.clear();
    });
    return SensorSnapshot.empty;
  }

  /// The registered sources, in no particular order.
  Iterable<SensorSource> get sources => _sources.values;

  /// Adds [source] and subscribes to its readings.
  ///
  /// A source registered under an id that is already taken replaces the one
  /// that was there, which is what re-pairing the same device does.
  void register(SensorSource source) {
    unregister(source.id);
    _sources[source.id] = source;
    _subscriptions[source.id] = source.readings.listen(
      _onReading,
      // One misbehaving sensor must not take the others down with it, and it
      // certainly must not take the recording down.
      onError: (Object error, StackTrace stackTrace) =>
          _log.warning('sensor ${source.id} failed', error, stackTrace),
    );
  }

  /// Removes the source with [id] and forgets what it reported.
  void unregister(String id) {
    final subscription = _subscriptions.remove(id);
    if (subscription != null) unawaited(subscription.cancel());
    final known = _sources.remove(id) != null;
    final had = _latest.remove(id) != null;
    if (known || had) _publish(_now());
  }

  /// Recomputes the snapshot as it stands at [now] and publishes it.
  ///
  /// The screens do not need this — every reading publishes on its own — but a
  /// caller that wants the staleness applied without waiting for the next
  /// reading does.
  void refresh([DateTime? now]) => _publish(now ?? _now());

  void _onReading(SensorReading reading) {
    if (!_sources.containsKey(reading.sourceId)) return;
    (_latest[reading.sourceId] ??=
            <SensorKind, SensorReading>{})[reading.kind] =
        reading;
    _publish(reading.at);
  }

  /// The instant the resolution is made against when no reading supplies one:
  /// the newest reading the hub holds, or the wall clock while it holds none.
  DateTime _now() {
    DateTime? newest;
    for (final readings in _latest.values) {
      for (final reading in readings.values) {
        if (newest == null || reading.at.isAfter(newest)) newest = reading.at;
      }
    }
    return newest ?? DateTime.now();
  }

  void _publish(DateTime now) {
    final winners = <SensorKind, SensorReading>{};
    final live = <String>{};
    for (final entry in _latest.entries) {
      final priority = _sources[entry.key]?.priority ?? 0;
      for (final reading in entry.value.values) {
        if (now.difference(reading.at).abs() > sensorStaleness) continue;
        live.add(entry.key);
        final best = winners[reading.kind];
        final bestPriority = best == null
            ? -1
            : _sources[best.sourceId]?.priority ?? 0;
        // Same source ranking: the newer reading wins, which is what a second
        // reading from the one source in the same window means.
        if (best == null ||
            priority > bestPriority ||
            (priority == bestPriority && reading.at.isAfter(best.at))) {
          winners[reading.kind] = reading;
        }
      }
    }

    final heartRate = winners[SensorKind.heartRate];
    final cadence = winners[SensorKind.cadence];
    final speed = winners[SensorKind.speed];
    final power = winners[SensorKind.power];
    state = SensorSnapshot(
      heartRateBpm: heartRate?.rounded,
      cadenceRpm: cadence?.rounded,
      speedMps: speed?.value,
      powerW: power?.rounded,
      heartRateAt: heartRate?.at,
      cadenceAt: cadence?.at,
      speedAt: speed?.at,
      powerAt: power?.at,
      liveSourceIds: Set<String>.unmodifiable(live),
    );
  }
}
