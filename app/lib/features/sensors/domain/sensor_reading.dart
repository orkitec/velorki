import 'package:flutter/foundation.dart';

/// What a sensor measures.
enum SensorKind {
  /// Heart rate in beats per minute.
  heartRate,

  /// Pedalling cadence in revolutions per minute.
  cadence,

  /// Ground speed in metres per second, from a wheel sensor rather than GPS.
  speed,

  /// Power at the pedals in watts.
  power,
}

/// One measurement from one sensor.
///
/// [value] is in the unit of its [kind]: beats per minute, revolutions per
/// minute, metres per second, watts. The values are kept as `double` because
/// that is what every transport delivers; rounding to the integer a track
/// point stores happens once, where the reading is used.
@immutable
class SensorReading {
  /// Creates a reading.
  const SensorReading({
    required this.kind,
    required this.value,
    required this.at,
    required this.sourceId,
  });

  /// What was measured.
  final SensorKind kind;

  /// The measurement, in the unit of [kind].
  final double value;

  /// When it was taken.
  final DateTime at;

  /// The [SensorSource] it came from.
  final String sourceId;

  /// The value rounded to the integer a track point stores.
  int get rounded => value.round();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorReading &&
          other.kind == kind &&
          other.value == value &&
          other.at == at &&
          other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(kind, value, at, sourceId);

  @override
  String toString() => 'SensorReading(${kind.name} $value from $sourceId, $at)';
}
