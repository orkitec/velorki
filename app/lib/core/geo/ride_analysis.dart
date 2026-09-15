import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

import '../units/units.dart';
import 'ride_stats.dart';

/// The most samples a ride chart ever carries.
///
/// A three hour ride is ten thousand fixes and fl_chart draws every one of
/// them; four hundred is more than a phone screen has pixels for the line
/// anyway, so the charts stay cheap however long the ride was.
const int rideChartMaxSamples = 400;

/// How many speed classes the coloured track is drawn in.
const int speedClassCount = 5;

/// The quantiles the speed classes are cut at.
///
/// Fixed thresholds would paint a whole commute in one colour and a whole
/// descent in another; cutting at the ride's own quantiles means every ride
/// shows its slow and its fast parts.
const List<double> speedClassQuantiles = <double>[0.2, 0.4, 0.6, 0.8];

/// How long a window the chart smoothing runs over: five samples of median
/// followed by five of mean, which takes the GPS spikes out without flattening
/// a real climb.
const int chartSmoothingWindow = 5;

/// One whole kilometre or mile of a ride, plus the remainder at the end.
class Split {
  /// Creates a split.
  const Split({
    required this.index,
    required this.distanceM,
    required this.movingTime,
    required this.ascentM,
    required this.descentM,
    required this.partial,
  });

  /// Position in the ride, counting from zero.
  final int index;

  /// How long this split is in metres: the split length, except for a
  /// [partial] one.
  final double distanceM;

  /// Time spent moving inside the split.
  final Duration movingTime;

  /// Metres climbed in the split, with [elevationHysteresisM] of hysteresis.
  final double ascentM;

  /// Metres descended in the split.
  final double descentM;

  /// Whether this is the remainder at the end rather than a whole split.
  final bool partial;

  /// Distance divided by moving time; zero while nothing moved.
  double get avgSpeedMps {
    final seconds = movingTime.inMicroseconds / Duration.microsecondsPerSecond;
    return seconds <= 0 ? 0 : distanceM / seconds;
  }

  @override
  String toString() =>
      'Split(${index + 1}: ${distanceM.round()} m, $movingTime, '
      '+${ascentM.round()} m${partial ? ', partial' : ''})';
}

/// One point of the elevation and speed charts.
class ChartSample {
  /// Creates a sample.
  const ChartSample({
    required this.distanceM,
    required this.speedMps,
    this.elevationM,
  });

  /// Distance from the start in metres.
  final double distanceM;

  /// Ground speed in metres per second, smoothed.
  final double speedMps;

  /// Elevation in metres, smoothed; `null` where the track carried none.
  final double? elevationM;

  @override
  String toString() =>
      'ChartSample(${distanceM.round()} m, ${speedMps.toStringAsFixed(1)} m/s, '
      '${elevationM?.round()} m)';
}

/// A stretch of track that was ridden at roughly one speed.
class SpeedBandSegment {
  /// Creates a segment.
  const SpeedBandSegment({required this.points, required this.speedClass});

  /// The polyline, at least two points.
  final List<LatLng> points;

  /// Which of the [speedClassCount] classes it falls in, 0 slowest.
  final int speedClass;

  /// The class as a fraction from 0 (slowest) to 1 (fastest), which is what
  /// the map colours the line by.
  double get t => speedClass / (speedClassCount - 1);

  @override
  String toString() =>
      'SpeedBandSegment(${points.length} points, class $speedClass)';
}

/// The track cut into [SpeedBandSegment]s by the ride's own speed quantiles.
class SpeedBands {
  /// Creates a set of bands.
  const SpeedBands({required this.segments, required this.thresholdsMps});

  /// A ride with nothing to colour.
  static const SpeedBands empty = SpeedBands(
    segments: <SpeedBandSegment>[],
    thresholdsMps: <double>[],
  );

  /// The segments, in riding order.
  final List<SpeedBandSegment> segments;

  /// The [speedClassQuantiles] of the ride's segment speeds, in m/s; empty
  /// when there was nothing to measure.
  final List<double> thresholdsMps;

  /// Whether there is anything to draw.
  bool get isEmpty => segments.isEmpty;

  @override
  String toString() => 'SpeedBands(${segments.length} segments)';
}

/// Everything the ride page shows beyond the plain figures: the splits, the
/// chart samples and the colouring of the track.
class RideAnalysis {
  /// Creates an analysis.
  const RideAnalysis({
    required this.splits,
    required this.samples,
    required this.speedBands,
    required this.splitLengthM,
  });

  /// A ride with nothing in it.
  static const RideAnalysis empty = RideAnalysis(
    splits: <Split>[],
    samples: <ChartSample>[],
    speedBands: SpeedBands.empty,
    splitLengthM: metersPerKilometer,
  );

  /// One entry per whole split, the remainder last.
  final List<Split> splits;

  /// The chart samples, at most [rideChartMaxSamples] of them.
  final List<ChartSample> samples;

  /// The track cut into speed classes.
  final SpeedBands speedBands;

  /// How long a split is in metres: a kilometre or a mile.
  final double splitLengthM;

  /// Whether there is an elevation chart to draw.
  bool get hasElevation =>
      _spansDistance && samples.where((s) => s.elevationM != null).length >= 2;

  /// Whether there is a speed chart to draw.
  bool get hasSpeed => _spansDistance && samples.any((s) => s.speedMps > 0);

  bool get _spansDistance => samples.length >= 2 && samples.last.distanceM > 0;

  @override
  String toString() =>
      'RideAnalysis(${splits.length} splits, ${samples.length} samples, '
      '$speedBands)';
}

/// Measures [points] for the ride page.
///
/// [splitLengthM] is a kilometre or a mile, [breaks] the stretches the
/// recorder was switched off in — the same ones [computeRideStats] is given,
/// so the splits add up to the figures above them. Fixes are accepted and
/// rejected exactly as [RideStatsAccumulator] does it, which is what keeps the
/// two from disagreeing.
RideAnalysis analyseRide(
  List<TrackPoint> points, {
  double splitLengthM = metersPerKilometer,
  List<StatsBreak> breaks = const <StatsBreak>[],
  Duration pauseGap = statsPauseGap,
  int maxSamples = rideChartMaxSamples,
  double hysteresisM = elevationHysteresisM,
}) {
  if (points.length < 2 || splitLengthM <= 0) {
    return RideAnalysis(
      splits: const <Split>[],
      samples: const <ChartSample>[],
      speedBands: SpeedBands.empty,
      splitLengthM: splitLengthM <= 0 ? metersPerKilometer : splitLengthM,
    );
  }
  final walk = _walk(points, breaks: breaks, pauseGap: pauseGap);
  return RideAnalysis(
    splits: _splits(walk, splitLengthM: splitLengthM, hysteresisM: hysteresisM),
    samples: _samples(walk, maxSamples: maxSamples),
    speedBands: _speedBands(walk),
    splitLengthM: splitLengthM,
  );
}

// ------------------------------------------------------------------- walk

/// One accepted step from a fix to the next.
class _Leg {
  _Leg({
    required this.fromIndex,
    required this.toIndex,
    required this.meters,
    required this.duration,
    required this.moving,
    required this.speedMps,
    required this.isBreak,
  });

  final int fromIndex;
  final int toIndex;

  /// Ground distance of the step; zero as far as the ride is concerned when
  /// [isBreak].
  final double meters;
  final Duration duration;
  final bool moving;
  final double speedMps;

  /// Whether the step crosses a pause: it contributes neither distance nor
  /// moving time, and neither climb nor colour.
  final bool isBreak;
}

/// The track as the statistics see it: the accepted steps and how far along
/// each fix is.
class _Walk {
  _Walk(this.points, this.legs, this.distanceAt, this.firstIndex);

  final List<TrackPoint> points;
  final List<_Leg> legs;

  /// Distance from the start for every fix, in metres.
  final List<double> distanceAt;

  /// The first accepted fix, or `-1` when there was none.
  final int firstIndex;

  /// The ridden length of the whole track.
  double get totalM => legs.isEmpty ? 0 : distanceAt[legs.last.toIndex];
}

_Walk _walk(
  List<TrackPoint> points, {
  required List<StatsBreak> breaks,
  required Duration pauseGap,
}) {
  final legs = <_Leg>[];
  final distanceAt = List<double>.filled(points.length, 0);
  var running = 0.0;
  var previousIndex = -1;

  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    if (previousIndex < 0) {
      previousIndex = i;
      distanceAt[i] = 0;
      continue;
    }
    final previous = points[previousIndex];
    final from = previous.time;
    final to = point.time;
    final meters = haversineMeters(previous.pos, point.pos);
    Duration? delta;
    var seconds = 0.0;
    if (from != null && to != null) {
      delta = to.difference(from);
      // A duplicate or an out-of-order fix is no fix at all, and neither is a
      // jump no bicycle could have made.
      if (delta <= Duration.zero) {
        distanceAt[i] = running;
        continue;
      }
      seconds = delta.inMicroseconds / Duration.microsecondsPerSecond;
      if (meters / seconds > maxPlausibleSpeedMps) {
        distanceAt[i] = running;
        continue;
      }
    }

    final isBreak =
        delta == null || delta > pauseGap || _spansBreak(breaks, from, to);
    if (!isBreak) {
      final measured = meters / seconds;
      final reported = _finite(point.speedMps);
      final speed =
          reported != null && reported >= 0 && reported <= maxPlausibleSpeedMps
          ? reported
          : measured;
      running += meters;
      legs.add(
        _Leg(
          fromIndex: previousIndex,
          toIndex: i,
          meters: meters,
          duration: delta,
          moving: measured >= movingSpeedThresholdMps,
          speedMps: speed,
          isBreak: false,
        ),
      );
    } else {
      legs.add(
        _Leg(
          fromIndex: previousIndex,
          toIndex: i,
          meters: 0,
          duration: delta ?? Duration.zero,
          moving: false,
          speedMps: 0,
          isBreak: true,
        ),
      );
    }
    distanceAt[i] = running;
    previousIndex = i;
  }

  return _Walk(
    points,
    legs,
    distanceAt,
    legs.isEmpty ? -1 : legs.first.fromIndex,
  );
}

bool _spansBreak(List<StatsBreak> breaks, DateTime? from, DateTime? to) {
  if (breaks.isEmpty || from == null || to == null) return false;
  for (final gap in breaks) {
    if (gap.spans(from, to)) return true;
  }
  return false;
}

double? _finite(double? value) =>
    value == null || !value.isFinite ? null : value;

// ----------------------------------------------------------------- splits

/// A remainder shorter than this is folded into the split before it rather
/// than given a row of its own.
const double _shortestSplitM = 10;

class _SplitBuilder {
  _SplitBuilder(this.index);

  final int index;
  double distanceM = 0;
  int movingMicros = 0;
  double ascentM = 0;
  double descentM = 0;
}

List<Split> _splits(
  _Walk walk, {
  required double splitLengthM,
  required double hysteresisM,
}) {
  final builders = <int, _SplitBuilder>{};
  _SplitBuilder builder(int index) =>
      builders.putIfAbsent(index, () => _SplitBuilder(index));

  // Distance and moving time are cut at the split boundary rather than handed
  // to whichever split a fix happens to fall in: at one fix a second a whole
  // segment is metres long, but an imported ride can carry one every minute.
  var cursor = 0.0;
  for (final leg in walk.legs) {
    if (leg.isBreak || leg.meters <= 0) continue;
    final micros = leg.moving ? leg.duration.inMicroseconds : 0;
    var start = cursor;
    var remaining = leg.meters;
    while (remaining > 1e-9) {
      final index = (start / splitLengthM).floor();
      final boundary = (index + 1) * splitLengthM;
      final take = math.min(remaining, math.max(boundary - start, 1e-9));
      final share = take / leg.meters;
      builder(index).distanceM += take;
      builder(index).movingMicros += (micros * share).round();
      start += take;
      remaining -= take;
    }
    cursor += leg.meters;
  }

  // The climb uses one anchor across the whole ride, exactly as the ride's own
  // ascent does, and every accepted step is booked to the split it ended in.
  // So the splits always add up to the figure in the tiles above them.
  double? anchor = walk.firstIndex < 0
      ? null
      : _finite(walk.points[walk.firstIndex].ele);
  for (final leg in walk.legs) {
    final value = _finite(walk.points[leg.toIndex].ele);
    if (value == null) continue;
    if (leg.isBreak || anchor == null) {
      // Nothing was ridden across the gap, so the height difference over it is
      // not a climb; the far side simply becomes the new anchor.
      anchor = value;
      continue;
    }
    final delta = value - anchor;
    if (delta.abs() < hysteresisM) continue;
    final index = (walk.distanceAt[leg.toIndex] / splitLengthM).floor();
    if (delta > 0) {
      builder(index).ascentM += delta;
    } else {
      builder(index).descentM += -delta;
    }
    anchor = value;
  }

  if (builders.isEmpty) return const <Split>[];
  var last = builders.keys.reduce(math.max);
  // A ride that ends ten metres past a boundary would otherwise get a row
  // reading "0 km" and "00:00"; those metres belong to the split before it.
  final tail = builders[last];
  if (last > 0 && tail != null && tail.distanceM < _shortestSplitM) {
    final previous = builder(last - 1);
    previous.distanceM += tail.distanceM;
    previous.movingMicros += tail.movingMicros;
    previous.ascentM += tail.ascentM;
    previous.descentM += tail.descentM;
    builders.remove(last);
    last -= 1;
  }
  return <Split>[
    for (var i = 0; i <= last; i++)
      if (builders[i] case final _SplitBuilder b)
        Split(
          index: i,
          distanceM: b.distanceM,
          movingTime: Duration(microseconds: b.movingMicros),
          ascentM: b.ascentM,
          descentM: b.descentM,
          // A metre of tolerance: the last split of a ride that ends on a
          // round kilometre is a whole one, floating point notwithstanding.
          partial: i == last && b.distanceM < splitLengthM - 1,
        )
      else
        Split(
          index: i,
          distanceM: 0,
          movingTime: Duration.zero,
          ascentM: 0,
          descentM: 0,
          partial: false,
        ),
  ];
}

// ---------------------------------------------------------------- samples

class _RawSample {
  _RawSample(this.distanceM, this.elevationM, this.speedMps);

  final double distanceM;
  double? elevationM;
  double speedMps;
}

List<ChartSample> _samples(_Walk walk, {required int maxSamples}) {
  if (walk.firstIndex < 0) return const <ChartSample>[];
  final raw = <_RawSample>[
    _RawSample(0, _finite(walk.points[walk.firstIndex].ele), 0),
    for (final leg in walk.legs)
      _RawSample(
        walk.distanceAt[leg.toIndex],
        _finite(walk.points[leg.toIndex].ele),
        leg.isBreak ? 0 : leg.speedMps,
      ),
  ];
  if (raw.length < 2) return const <ChartSample>[];
  // The first fix has no step behind it, so it borrows the speed of the one
  // in front rather than starting the chart at a standstill that never was.
  raw.first.speedMps = raw[1].speedMps;

  _smoothInPlace(raw);
  return _resample(raw, maxSamples);
}

/// Takes the spikes out of the two series: a five point median first, which
/// drops a single bad fix outright, then a five point mean, which makes what
/// is left a line instead of a staircase.
void _smoothInPlace(List<_RawSample> raw) {
  final speeds = <double>[for (final s in raw) s.speedMps];
  final smoothedSpeeds = _movingMean(
    _movingMedian(speeds, chartSmoothingWindow),
    chartSmoothingWindow,
  );
  for (var i = 0; i < raw.length; i++) {
    raw[i].speedMps = smoothedSpeeds[i];
  }

  // Only the fixes that actually carried a height take part, so a gap in the
  // elevation does not pull the line towards zero.
  final withElevation = <int>[
    for (var i = 0; i < raw.length; i++)
      if (raw[i].elevationM != null) i,
  ];
  if (withElevation.length < 2) return;
  final elevations = <double>[
    for (final i in withElevation) raw[i].elevationM!,
  ];
  final smoothed = _movingMean(
    _movingMedian(elevations, chartSmoothingWindow),
    chartSmoothingWindow,
  );
  for (var k = 0; k < withElevation.length; k++) {
    raw[withElevation[k]].elevationM = smoothed[k];
  }
}

List<double> _movingMedian(List<double> values, int window) {
  if (values.length < window) return List<double>.of(values);
  final half = window ~/ 2;
  final out = List<double>.filled(values.length, 0);
  final buffer = List<double>.filled(window, 0);
  for (var i = 0; i < values.length; i++) {
    final start = (i - half).clamp(0, values.length - window);
    for (var k = 0; k < window; k++) {
      buffer[k] = values[start + k];
    }
    buffer.sort();
    out[i] = buffer[half];
  }
  return out;
}

List<double> _movingMean(List<double> values, int window) {
  if (values.length < window) return List<double>.of(values);
  final half = window ~/ 2;
  final out = List<double>.filled(values.length, 0);
  for (var i = 0; i < values.length; i++) {
    final start = math.max(0, i - half);
    final end = math.min(values.length - 1, i + half);
    var sum = 0.0;
    for (var k = start; k <= end; k++) {
      sum += values[k];
    }
    out[i] = sum / (end - start + 1);
  }
  return out;
}

/// Thins [raw] to [maxSamples] points spaced evenly along the *distance*, not
/// along the fix count: a ride that stood still for ten minutes must not spend
/// a quarter of the chart on that one spot.
List<ChartSample> _resample(List<_RawSample> raw, int maxSamples) {
  ChartSample toSample(_RawSample s) => ChartSample(
    distanceM: s.distanceM,
    speedMps: s.speedMps,
    elevationM: s.elevationM,
  );
  if (maxSamples < 2 || raw.length <= maxSamples) {
    return <ChartSample>[for (final s in raw) toSample(s)];
  }
  final total = raw.last.distanceM;
  if (total <= 0) {
    // Nothing was ridden; thin by index so the chart at least draws.
    final stride = (raw.length / maxSamples).ceil();
    return <ChartSample>[
      for (var i = 0; i < raw.length; i += stride) toSample(raw[i]),
      toSample(raw.last),
    ];
  }

  final out = <ChartSample>[];
  var cursor = 0;
  for (var k = 0; k < maxSamples; k++) {
    final target = total * k / (maxSamples - 1);
    while (cursor < raw.length - 2 && raw[cursor + 1].distanceM < target) {
      cursor++;
    }
    final a = raw[cursor];
    final b = raw[math.min(cursor + 1, raw.length - 1)];
    final span = b.distanceM - a.distanceM;
    final f = span <= 0 ? 0.0 : ((target - a.distanceM) / span).clamp(0.0, 1.0);
    out.add(
      ChartSample(
        distanceM: target,
        speedMps: a.speedMps + (b.speedMps - a.speedMps) * f,
        elevationM: _lerpOrNull(a.elevationM, b.elevationM, f),
      ),
    );
  }
  return out;
}

double? _lerpOrNull(double? a, double? b, double f) {
  if (a == null) return b;
  if (b == null) return a;
  return a + (b - a) * f;
}

// ------------------------------------------------------------ speed bands

SpeedBands _speedBands(_Walk walk) {
  final ridden = <_Leg>[
    for (final leg in walk.legs)
      if (!leg.isBreak && leg.meters > 0) leg,
  ];
  if (ridden.isEmpty) return SpeedBands.empty;

  final sorted = <double>[for (final leg in ridden) leg.speedMps]..sort();
  final thresholds = <double>[
    for (final q in speedClassQuantiles) _quantile(sorted, q),
  ];
  // A ride at one speed throughout has no quantiles worth the name; drawing it
  // all in the middle colour is honest, five shades of noise are not.
  final flat = thresholds.last - thresholds.first < 1e-6;

  final segments = <SpeedBandSegment>[];
  var current = <LatLng>[];
  var currentClass = -1;

  void flush() {
    if (current.length >= 2) {
      segments.add(
        SpeedBandSegment(
          points: List<LatLng>.unmodifiable(current),
          speedClass: currentClass,
        ),
      );
    }
    current = <LatLng>[];
    currentClass = -1;
  }

  for (final leg in walk.legs) {
    if (leg.isBreak || leg.meters <= 0) {
      // The straight line across a pause was never ridden, so it is not drawn.
      flush();
      continue;
    }
    final speedClass = flat
        ? speedClassCount ~/ 2
        : _classOf(leg.speedMps, thresholds);
    if (current.isEmpty) {
      currentClass = speedClass;
      current = <LatLng>[
        walk.points[leg.fromIndex].pos,
        walk.points[leg.toIndex].pos,
      ];
    } else if (speedClass == currentClass) {
      current.add(walk.points[leg.toIndex].pos);
    } else {
      // The segments meet at the fix between them, so the colours touch
      // instead of leaving a hole in the line.
      final join = walk.points[leg.fromIndex].pos;
      flush();
      currentClass = speedClass;
      current = <LatLng>[join, walk.points[leg.toIndex].pos];
    }
  }
  flush();

  return SpeedBands(
    segments: List<SpeedBandSegment>.unmodifiable(segments),
    thresholdsMps: List<double>.unmodifiable(thresholds),
  );
}

/// The [q] quantile of the ascending [sorted], interpolated between the two
/// neighbouring values.
double _quantile(List<double> sorted, double q) {
  if (sorted.isEmpty) return 0;
  if (sorted.length == 1) return sorted.first;
  final position = (sorted.length - 1) * q;
  final low = position.floor();
  final high = math.min(low + 1, sorted.length - 1);
  final f = position - low;
  return sorted[low] + (sorted[high] - sorted[low]) * f;
}

int _classOf(double speed, List<double> thresholds) {
  for (var i = 0; i < thresholds.length; i++) {
    if (speed < thresholds[i]) return i;
  }
  return thresholds.length;
}
