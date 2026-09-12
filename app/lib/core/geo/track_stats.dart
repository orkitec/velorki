import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// Speed below which a rider counts as stopped, in metres per second.
///
/// 1 km/h. GPS noise makes a parked bike wander by a few metres a second, so
/// anything slower than walking pace is not riding.
const double movingSpeedThresholdMps = 1000.0 / 3600.0;

/// Elevation change a climb or descent has to reach before it is counted, in
/// metres.
///
/// Barometric and GPS altitudes jitter by a metre or two; without hysteresis a
/// flat ride accumulates hundreds of metres of "ascent".
const double ascentHysteresisM = 3.0;

/// Everything the `rides` table wants to know about a track.
///
/// Produced by [computeTrackStats]; every field is derived from the track
/// points alone, so the same numbers come out of an imported file and out of a
/// recording.
class TrackStats {
  /// Creates a statistics record.
  const TrackStats({
    required this.distanceM,
    required this.movingTime,
    required this.elapsedTime,
    required this.ascentM,
    required this.descentM,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    this.startedAt,
    this.endedAt,
  });

  /// A record for a track with no usable points.
  static const TrackStats empty = TrackStats(
    distanceM: 0,
    movingTime: Duration.zero,
    elapsedTime: Duration.zero,
    ascentM: 0,
    descentM: 0,
    avgSpeedMps: 0,
    maxSpeedMps: 0,
  );

  /// Great-circle length of the track in metres.
  final double distanceM;

  /// Time spent above [movingSpeedThresholdMps].
  final Duration movingTime;

  /// Wall-clock time between the first and the last timestamp.
  final Duration elapsedTime;

  /// Metres climbed, with [ascentHysteresisM] hysteresis.
  final double ascentM;

  /// Metres descended, with [ascentHysteresisM] hysteresis.
  final double descentM;

  /// [distanceM] divided by [movingTime]; zero when nothing moved.
  final double avgSpeedMps;

  /// Fastest segment speed, or the fastest reported [TrackPoint.speedMps]
  /// when the points carry one.
  final double maxSpeedMps;

  /// Timestamp of the first point that had one.
  final DateTime? startedAt;

  /// Timestamp of the last point that had one.
  final DateTime? endedAt;

  /// Whether the track carried timestamps at all.
  bool get hasTime => startedAt != null && endedAt != null;

  @override
  String toString() =>
      'TrackStats(${distanceM.toStringAsFixed(1)} m, moving $movingTime, '
      'elapsed $elapsedTime, +${ascentM.toStringAsFixed(1)} '
      '-${descentM.toStringAsFixed(1)})';
}

/// Total great-circle length of [points] in metres.
double trackDistanceMeters(List<TrackPoint> points) =>
    polylineLengthMeters(points.map((p) => p.pos).toList(growable: false));

/// The time span covered by [points], ignoring points without a timestamp.
///
/// Returns [Duration.zero] when fewer than two points carry a time.
Duration elapsedTimeOf(List<TrackPoint> points) {
  final first = _firstTime(points);
  final last = _lastTime(points);
  if (first == null || last == null) return Duration.zero;
  final span = last.difference(first);
  return span.isNegative ? Duration.zero : span;
}

/// Time spent riding, i.e. the sum of the segments whose average speed is at
/// least [thresholdMps].
///
/// Only consecutive pairs that both carry a timestamp contribute, so a file
/// without times yields [Duration.zero]. Segments with a non-positive or
/// backwards time step are skipped rather than counted as infinitely fast.
Duration movingTimeOf(
  List<TrackPoint> points, {
  double thresholdMps = movingSpeedThresholdMps,
}) {
  var micros = 0;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final ta = a.time;
    final tb = b.time;
    if (ta == null || tb == null) continue;
    final stepMicros = tb.difference(ta).inMicroseconds;
    if (stepMicros <= 0) continue;
    final seconds = stepMicros / Duration.microsecondsPerSecond;
    final speed = haversineMeters(a.pos, b.pos) / seconds;
    if (speed >= thresholdMps) micros += stepMicros;
  }
  return Duration(microseconds: micros);
}

/// Metres climbed and descended, counted only once the elevation has moved
/// [hysteresisM] away from the last confirmed level.
///
/// One running reference is kept. A point at least [hysteresisM] above it
/// books the whole difference as ascent and becomes the new reference; a point
/// at least [hysteresisM] below it does the same for descent. Anything in
/// between is noise and is ignored, so a flat ride reports zero instead of the
/// few hundred metres GPS jitter would otherwise accumulate. Points without an
/// elevation are skipped.
({double ascentM, double descentM}) elevationChange(
  List<TrackPoint> points, {
  double hysteresisM = ascentHysteresisM,
}) {
  double? reference;
  var ascent = 0.0;
  var descent = 0.0;

  for (final point in points) {
    final ele = point.ele;
    if (ele == null || ele.isNaN) continue;
    if (reference == null) {
      reference = ele;
      continue;
    }
    if (ele - reference >= hysteresisM) {
      ascent += ele - reference;
      reference = ele;
    } else if (reference - ele >= hysteresisM) {
      descent += reference - ele;
      reference = ele;
    }
  }

  return (ascentM: ascent, descentM: descent);
}

/// The fastest speed seen along [points], in metres per second.
///
/// Points that report their own [TrackPoint.speedMps] are trusted; otherwise
/// the speed of each timed segment is used. Segments shorter than a second are
/// still counted, but a zero or backwards time step is skipped.
double maxSpeedOf(List<TrackPoint> points) {
  var max = 0.0;
  var sawReported = false;
  for (final point in points) {
    final reported = point.speedMps;
    if (reported != null && !reported.isNaN && reported >= 0) {
      sawReported = true;
      max = math.max(max, reported);
    }
  }
  if (sawReported) return max;

  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final ta = a.time;
    final tb = b.time;
    if (ta == null || tb == null) continue;
    final stepMicros = tb.difference(ta).inMicroseconds;
    if (stepMicros <= 0) continue;
    final seconds = stepMicros / Duration.microsecondsPerSecond;
    max = math.max(max, haversineMeters(a.pos, b.pos) / seconds);
  }
  return max;
}

/// Every statistic the `rides` table stores, computed from [points].
///
/// [thresholdMps] is the speed below which the rider counts as stopped and
/// [hysteresisM] the elevation change a climb has to reach before it is
/// booked; the defaults are the ones the architecture document fixes (1 km/h
/// and 3 m).
TrackStats computeTrackStats(
  List<TrackPoint> points, {
  double thresholdMps = movingSpeedThresholdMps,
  double hysteresisM = ascentHysteresisM,
}) {
  if (points.isEmpty) return TrackStats.empty;

  final distance = trackDistanceMeters(points);
  final moving = movingTimeOf(points, thresholdMps: thresholdMps);
  final elapsed = elapsedTimeOf(points);
  final elevation = elevationChange(points, hysteresisM: hysteresisM);
  final movingSeconds = moving.inMicroseconds / Duration.microsecondsPerSecond;

  return TrackStats(
    distanceM: distance,
    movingTime: moving,
    elapsedTime: elapsed,
    ascentM: elevation.ascentM,
    descentM: elevation.descentM,
    avgSpeedMps: movingSeconds > 0 ? distance / movingSeconds : 0.0,
    maxSpeedMps: maxSpeedOf(points),
    startedAt: _firstTime(points),
    endedAt: _lastTime(points),
  );
}

DateTime? _firstTime(List<TrackPoint> points) {
  for (final point in points) {
    final time = point.time;
    if (time != null) return time;
  }
  return null;
}

DateTime? _lastTime(List<TrackPoint> points) {
  for (var i = points.length - 1; i >= 0; i--) {
    final time = points[i].time;
    if (time != null) return time;
  }
  return null;
}
