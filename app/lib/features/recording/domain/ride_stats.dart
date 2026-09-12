import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Below this speed the rider counts as standing still: 1 km/h, the threshold
/// the architecture notes fix for moving time and for auto-pause.
const double movingSpeedThresholdMps = 1000 / 3600;

/// A climb or descent only counts once it exceeds this many metres from the
/// last anchor. Without the hysteresis the noise of a barometer-less GPS adds
/// hundreds of phantom metres to an hour of riding.
const double elevationHysteresisM = 3;

/// Anything faster than this is a GPS jump, not a bicycle: the fix is dropped
/// instead of poisoning distance and maximum speed. 30 m/s is 108 km/h.
const double maxPlausibleSpeedMps = 30;

/// A gap between two fixes longer than this is treated as a break: the segment
/// contributes neither distance nor moving time.
///
/// This is what makes a paused recording add up correctly. The recorder stops
/// journalling while the ride is paused, so the pause shows up as a long gap —
/// and the very same rule runs live in [RideStatsAccumulator] and afterwards in
/// [computeRideStats], so the number on the screen is the number that is saved.
const Duration statsPauseGap = Duration(seconds: 30);

/// Everything the `rides` table stores about how a ride went.
@immutable
class RideStats {
  /// Creates a set of statistics.
  const RideStats({
    this.distanceM = 0,
    this.movingTime = Duration.zero,
    this.elapsedTime = Duration.zero,
    this.ascentM = 0,
    this.descentM = 0,
    this.maxSpeedMps = 0,
    this.pointCount = 0,
    this.startedAt,
    this.endedAt,
  });

  /// A ride that has not started yet.
  static const RideStats empty = RideStats();

  /// Distance travelled in metres.
  final double distanceM;

  /// Time spent above [movingSpeedThresholdMps].
  final Duration movingTime;

  /// Wall-clock time between the first and the last fix.
  final Duration elapsedTime;

  /// Metres climbed, with [elevationHysteresisM] of hysteresis.
  final double ascentM;

  /// Metres descended, with [elevationHysteresisM] of hysteresis.
  final double descentM;

  /// Fastest plausible speed seen, in metres per second.
  final double maxSpeedMps;

  /// How many fixes went into these numbers.
  final int pointCount;

  /// Timestamp of the first fix, if any fix carried one.
  final DateTime? startedAt;

  /// Timestamp of the last fix, if any fix carried one.
  final DateTime? endedAt;

  /// Distance divided by moving time; zero while nothing has moved.
  double get avgSpeedMps {
    final seconds = movingTime.inMicroseconds / Duration.microsecondsPerSecond;
    return seconds <= 0 ? 0 : distanceM / seconds;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideStats &&
          other.distanceM == distanceM &&
          other.movingTime == movingTime &&
          other.elapsedTime == elapsedTime &&
          other.ascentM == ascentM &&
          other.descentM == descentM &&
          other.maxSpeedMps == maxSpeedMps &&
          other.pointCount == pointCount &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(
    distanceM,
    movingTime,
    elapsedTime,
    ascentM,
    descentM,
    maxSpeedMps,
    pointCount,
    startedAt,
    endedAt,
  );

  @override
  String toString() =>
      'RideStats(${distanceM.toStringAsFixed(1)} m, moving $movingTime, '
      'elapsed $elapsedTime, +${ascentM.toStringAsFixed(1)} '
      '-${descentM.toStringAsFixed(1)} m, $pointCount points)';
}

/// Folds track points into [RideStats], one fix at a time.
///
/// The recorder feeds it live while riding and [computeRideStats] feeds it the
/// whole journal afterwards, which is why the two can never disagree.
class RideStatsAccumulator {
  /// Creates an accumulator; the thresholds are only parameters so the tests
  /// can be written with round numbers.
  RideStatsAccumulator({
    this.pauseGap = statsPauseGap,
    this.movingThresholdMps = movingSpeedThresholdMps,
    this.hysteresisM = elevationHysteresisM,
    this.maxSpeedLimitMps = maxPlausibleSpeedMps,
  });

  /// A gap longer than this ends a segment; see [statsPauseGap].
  final Duration pauseGap;

  /// Speed from which a segment counts as moving.
  final double movingThresholdMps;

  /// Elevation hysteresis in metres.
  final double hysteresisM;

  /// Fixes implying a higher speed than this are dropped.
  final double maxSpeedLimitMps;

  double _distanceM = 0;
  int _movingMicros = 0;
  double _ascentM = 0;
  double _descentM = 0;
  double _maxSpeedMps = 0;
  int _pointCount = 0;
  double _lastSegmentSpeedMps = 0;
  TrackPoint? _last;
  DateTime? _firstTime;
  DateTime? _lastTime;
  DateTime? _lastMovingAt;
  double? _elevationAnchor;

  /// The statistics as they stand.
  RideStats get stats {
    final first = _firstTime;
    final last = _lastTime;
    return RideStats(
      distanceM: _distanceM,
      movingTime: Duration(microseconds: _movingMicros),
      elapsedTime: first == null || last == null
          ? Duration.zero
          : last.difference(first),
      ascentM: _ascentM,
      descentM: _descentM,
      maxSpeedMps: _maxSpeedMps,
      pointCount: _pointCount,
      startedAt: first,
      endedAt: last,
    );
  }

  /// Speed of the segment that ended at the last accepted fix, in m/s. Zero
  /// after a break, so a resumed recording does not look like it is moving.
  double get lastSegmentSpeedMps => _lastSegmentSpeedMps;

  /// Timestamp of the last fix that arrived above [movingThresholdMps].
  DateTime? get lastMovingAt => _lastMovingAt;

  /// The last accepted fix.
  TrackPoint? get lastPoint => _last;

  /// How many fixes were accepted.
  int get pointCount => _pointCount;

  /// Folds [point] in.
  ///
  /// Returns `false` when the fix was rejected — a duplicate or out-of-order
  /// timestamp, or a jump faster than [maxSpeedLimitMps]. A rejected fix
  /// changes nothing and must not be written to the journal either.
  bool add(TrackPoint point) {
    final previous = _last;
    if (previous == null) {
      _last = point;
      _pointCount = 1;
      final time = point.time;
      if (time != null) {
        _firstTime = time;
        _lastTime = time;
      }
      _elevationAnchor = _finite(point.ele);
      return true;
    }

    final from = previous.time;
    final to = point.time;
    final meters = haversineMeters(previous.pos, point.pos);
    Duration? delta;
    if (from != null && to != null) {
      delta = to.difference(from);
      if (delta <= Duration.zero) return false;
      final seconds = delta.inMicroseconds / Duration.microsecondsPerSecond;
      if (meters / seconds > maxSpeedLimitMps) return false;
    }

    if (delta == null || delta > pauseGap) {
      // A break: the straight line across it is not a ridden distance, and the
      // height difference across it is not a climb.
      _lastSegmentSpeedMps = 0;
      _elevationAnchor = _finite(point.ele) ?? _elevationAnchor;
    } else {
      final seconds = delta.inMicroseconds / Duration.microsecondsPerSecond;
      final measured = meters / seconds;
      _distanceM += meters;
      if (measured >= movingThresholdMps) {
        _movingMicros += delta.inMicroseconds;
        _lastMovingAt = to;
      }
      final reported = _finite(point.speedMps);
      final speed =
          reported != null && reported >= 0 && reported <= maxSpeedLimitMps
          ? reported
          : measured;
      _lastSegmentSpeedMps = speed;
      if (speed > _maxSpeedMps) _maxSpeedMps = speed;
      _accumulateElevation(point.ele);
    }

    _last = point;
    _pointCount++;
    if (to != null) {
      _firstTime ??= to;
      _lastTime = to;
    }
    return true;
  }

  void _accumulateElevation(double? elevation) {
    final value = _finite(elevation);
    if (value == null) return;
    final anchor = _elevationAnchor;
    if (anchor == null) {
      _elevationAnchor = value;
      return;
    }
    final delta = value - anchor;
    if (delta >= hysteresisM) {
      _ascentM += delta;
      _elevationAnchor = value;
    } else if (delta <= -hysteresisM) {
      _descentM += -delta;
      _elevationAnchor = value;
    }
  }

  static double? _finite(double? value) =>
      value == null || !value.isFinite ? null : value;
}

/// The statistics of a finished ride, from its track points.
RideStats computeRideStats(
  List<TrackPoint> points, {
  Duration pauseGap = statsPauseGap,
}) {
  final accumulator = RideStatsAccumulator(pauseGap: pauseGap);
  for (final point in points) {
    accumulator.add(point);
  }
  return accumulator.stats;
}
