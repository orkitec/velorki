import 'lat_lng.dart';

/// One sample of a track: a position plus whatever the source knew about it.
///
/// Planned routes carry [pos] and [ele]; recorded rides add [time], [speedMps]
/// and [accuracyM], and, when a sensor was paired, [heartRateBpm],
/// [cadenceRpm] and [powerW]. Absent values stay `null` all the way through
/// the packed codec. [headingDeg] is the live course of a fix; it is not
/// stored.
class TrackPoint {
  /// Creates a track point.
  const TrackPoint(
    this.pos, {
    this.ele,
    this.time,
    this.speedMps,
    this.accuracyM,
    this.headingDeg,
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerW,
  });

  /// The position.
  final LatLng pos;

  /// Elevation in metres above the ellipsoid, if known.
  final double? ele;

  /// Sample timestamp, if known.
  final DateTime? time;

  /// Ground speed in metres per second, if known.
  final double? speedMps;

  /// Horizontal accuracy in metres, if known.
  final double? accuracyM;

  /// Course over ground in degrees clockwise from north, if the fix had one.
  final double? headingDeg;

  /// Heart rate in beats per minute, if a sensor reported one.
  final int? heartRateBpm;

  /// Pedalling cadence in revolutions per minute, if a sensor reported one.
  ///
  /// Zero is a real reading — a rider freewheeling — so an absent value is
  /// `null` and never 0.
  final int? cadenceRpm;

  /// Power in watts, if a sensor reported one. Zero is a real reading.
  final int? powerW;

  /// Latitude shortcut.
  double get lat => pos.lat;

  /// Longitude shortcut.
  double get lon => pos.lon;

  /// Whether this point carries any sensor reading at all.
  bool get hasSensors =>
      heartRateBpm != null || cadenceRpm != null || powerW != null;

  /// A copy with the given fields replaced. Passing `null` keeps the old
  /// value; use [TrackPoint.new] to build a point without a field.
  TrackPoint copyWith({
    LatLng? pos,
    double? ele,
    DateTime? time,
    double? speedMps,
    double? accuracyM,
    double? headingDeg,
    int? heartRateBpm,
    int? cadenceRpm,
    int? powerW,
  }) => TrackPoint(
    pos ?? this.pos,
    ele: ele ?? this.ele,
    time: time ?? this.time,
    speedMps: speedMps ?? this.speedMps,
    accuracyM: accuracyM ?? this.accuracyM,
    headingDeg: headingDeg ?? this.headingDeg,
    heartRateBpm: heartRateBpm ?? this.heartRateBpm,
    cadenceRpm: cadenceRpm ?? this.cadenceRpm,
    powerW: powerW ?? this.powerW,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackPoint &&
          other.pos == pos &&
          other.ele == ele &&
          other.time == time &&
          other.speedMps == speedMps &&
          other.accuracyM == accuracyM &&
          other.headingDeg == headingDeg &&
          other.heartRateBpm == heartRateBpm &&
          other.cadenceRpm == cadenceRpm &&
          other.powerW == powerW;

  @override
  int get hashCode => Object.hash(
    pos,
    ele,
    time,
    speedMps,
    accuracyM,
    headingDeg,
    heartRateBpm,
    cadenceRpm,
    powerW,
  );

  @override
  String toString() =>
      'TrackPoint($pos, ele: $ele, time: $time, '
      'speed: $speedMps, acc: $accuracyM, heading: $headingDeg, '
      'hr: $heartRateBpm, cad: $cadenceRpm, power: $powerW)';
}
