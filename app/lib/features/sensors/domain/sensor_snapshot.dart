import 'package:flutter/foundation.dart';

import 'sensor_reading.dart';

/// How long a reading stands for after it arrived.
///
/// A strap reports every second or two; ten seconds of silence means the
/// rider has taken it off, walked away from it, or the connection has gone.
/// Past that the value is not shown and not stamped onto a fix — a frozen
/// heart rate is worse than none.
const Duration sensorStaleness = Duration(seconds: 10);

/// What the sensors are saying right now: one value per kind, each with the
/// moment it was measured.
///
/// The values are already resolved across the registered sources — the highest
/// priority source that was still reporting won — so a reader only has to
/// decide whether a value is fresh enough, which is what [readingsAt] does.
@immutable
class SensorSnapshot {
  /// Creates a snapshot.
  const SensorSnapshot({
    this.heartRateBpm,
    this.cadenceRpm,
    this.speedMps,
    this.powerW,
    this.heartRateAt,
    this.cadenceAt,
    this.speedAt,
    this.powerAt,
    this.liveSourceIds = const <String>{},
  });

  /// Reads a snapshot back from [toMap].
  factory SensorSnapshot.fromMap(Map<Object?, Object?> map) {
    DateTime? at(String key) {
      final ms = map[key] as num?;
      return ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true);
    }

    return SensorSnapshot(
      heartRateBpm: (map['heartRateBpm'] as num?)?.toInt(),
      cadenceRpm: (map['cadenceRpm'] as num?)?.toInt(),
      speedMps: (map['speedMps'] as num?)?.toDouble(),
      powerW: (map['powerW'] as num?)?.toInt(),
      heartRateAt: at('heartRateAt'),
      cadenceAt: at('cadenceAt'),
      speedAt: at('speedAt'),
      powerAt: at('powerAt'),
      liveSourceIds: <String>{
        for (final id in map['liveSourceIds'] as List<Object?>? ?? const [])
          if (id is String) id,
      },
    );
  }

  /// Nothing is reporting.
  static const SensorSnapshot empty = SensorSnapshot();

  /// Heart rate in beats per minute.
  final int? heartRateBpm;

  /// Cadence in revolutions per minute.
  final int? cadenceRpm;

  /// Wheel speed in metres per second; the GPS has its own.
  final double? speedMps;

  /// Power in watts.
  final int? powerW;

  /// When [heartRateBpm] was measured.
  final DateTime? heartRateAt;

  /// When [cadenceRpm] was measured.
  final DateTime? cadenceAt;

  /// When [speedMps] was measured.
  final DateTime? speedAt;

  /// When [powerW] was measured.
  final DateTime? powerAt;

  /// The sources that have reported something inside the staleness window.
  final Set<String> liveSourceIds;

  /// Whether any value is present at all, fresh or not.
  bool get isEmpty =>
      heartRateBpm == null &&
      cadenceRpm == null &&
      speedMps == null &&
      powerW == null;

  /// Whether any value is present at all.
  bool get isNotEmpty => !isEmpty;

  /// The timestamp of [kind], `null` when that kind has no value.
  DateTime? timestampOf(SensorKind kind) => switch (kind) {
    SensorKind.heartRate => heartRateAt,
    SensorKind.cadence => cadenceAt,
    SensorKind.speed => speedAt,
    SensorKind.power => powerAt,
  };

  /// This snapshot with everything older than [staleness] dropped.
  ///
  /// [liveSourceIds] is left as it stands: it describes which sources were
  /// reporting when the snapshot was taken, not which values survive here.
  SensorSnapshot readingsAt(
    DateTime now, {
    Duration staleness = sensorStaleness,
  }) {
    bool fresh(DateTime? at) =>
        at != null && now.difference(at).abs() <= staleness;

    final heartRate = fresh(heartRateAt);
    final cadence = fresh(cadenceAt);
    final speed = fresh(speedAt);
    final power = fresh(powerAt);
    if (heartRate && cadence && speed && power) return this;
    return SensorSnapshot(
      heartRateBpm: heartRate ? heartRateBpm : null,
      cadenceRpm: cadence ? cadenceRpm : null,
      speedMps: speed ? speedMps : null,
      powerW: power ? powerW : null,
      heartRateAt: heartRate ? heartRateAt : null,
      cadenceAt: cadence ? cadenceAt : null,
      speedAt: speed ? speedAt : null,
      powerAt: power ? powerAt : null,
      liveSourceIds: liveSourceIds,
    );
  }

  /// This snapshot as a plain map, for `FlutterForegroundTask.sendDataToTask`.
  Map<String, Object?> toMap() => <String, Object?>{
    if (heartRateBpm != null) 'heartRateBpm': heartRateBpm,
    if (cadenceRpm != null) 'cadenceRpm': cadenceRpm,
    if (speedMps != null) 'speedMps': speedMps,
    if (powerW != null) 'powerW': powerW,
    if (heartRateAt != null)
      'heartRateAt': heartRateAt!.toUtc().millisecondsSinceEpoch,
    if (cadenceAt != null)
      'cadenceAt': cadenceAt!.toUtc().millisecondsSinceEpoch,
    if (speedAt != null) 'speedAt': speedAt!.toUtc().millisecondsSinceEpoch,
    if (powerAt != null) 'powerAt': powerAt!.toUtc().millisecondsSinceEpoch,
    'liveSourceIds': liveSourceIds.toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorSnapshot &&
          other.heartRateBpm == heartRateBpm &&
          other.cadenceRpm == cadenceRpm &&
          other.speedMps == speedMps &&
          other.powerW == powerW &&
          other.heartRateAt == heartRateAt &&
          other.cadenceAt == cadenceAt &&
          other.speedAt == speedAt &&
          other.powerAt == powerAt &&
          setEquals(other.liveSourceIds, liveSourceIds);

  @override
  int get hashCode => Object.hash(
    heartRateBpm,
    cadenceRpm,
    speedMps,
    powerW,
    heartRateAt,
    cadenceAt,
    speedAt,
    powerAt,
    Object.hashAllUnordered(liveSourceIds),
  );

  @override
  String toString() =>
      'SensorSnapshot(hr: $heartRateBpm, cad: $cadenceRpm, '
      'speed: $speedMps, power: $powerW, live: $liveSourceIds)';
}
