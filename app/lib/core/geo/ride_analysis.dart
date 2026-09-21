import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

import '../units/units.dart';
import 'climbs.dart';
import 'power_metrics.dart';
import 'power_model.dart';
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

/// How far along the track, before and after a fix, the heights are averaged
/// over for the power estimate's grade: raw GPS heights swing metres between
/// fixes, and a grade taken from two raw fixes five metres apart is noise.
const double powerGradeSmoothingM = 20;

/// The steepest grade the power estimate believes, rise over run either way;
/// anything beyond it is a height that jumped.
const double powerGradeLimit = 0.25;

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

/// One point of the elevation, speed and heart rate charts.
class ChartSample {
  /// Creates a sample.
  const ChartSample({
    required this.distanceM,
    required this.speedMps,
    this.elevationM,
    this.heartRateBpm,
  });

  /// Distance from the start in metres.
  final double distanceM;

  /// Ground speed in metres per second, smoothed.
  final double speedMps;

  /// Elevation in metres, smoothed; `null` where the track carried none.
  final double? elevationM;

  /// Heart rate in beats per minute; `null` where no sensor reported one.
  ///
  /// Not smoothed: a strap already reports a filtered figure, and smoothing it
  /// again would only flatten the sprints out of the line.
  final int? heartRateBpm;

  @override
  String toString() =>
      'ChartSample(${distanceM.round()} m, ${speedMps.toStringAsFixed(1)} m/s, '
      '${elevationM?.round()} m, ${heartRateBpm ?? '-'} bpm)';
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

/// How hard the ride was, summed over the moving legs: what a calorie
/// estimate and a zone chart are built from.
///
/// All of it is integrated over time, leg by leg, so a ride with a fix every
/// second and one with a fix every minute come out the same. The heart-rate
/// figures are kept as a time and a beat-seconds sum rather than a mean, which
/// is what lets a formula linear in the heart rate integrate exactly.
class RideEffort {
  /// Creates the effort.
  const RideEffort({
    required this.movingTime,
    required this.maxCadenceRpm,
    required this.maxPowerW,
    required this.normalizedPowerW,
    required this.energyKj,
    required this.powerTime,
    required this.heartRateTime,
    required this.heartRateBeatSeconds,
    required this.metHours,
    required this.heartRateZones,
    required this.powerZones,
    required this.estimatedEnergyKj,
    required this.estimatedPowerTime,
  });

  /// A ride with nothing in it.
  static const RideEffort zero = RideEffort(
    movingTime: Duration.zero,
    maxCadenceRpm: null,
    maxPowerW: null,
    normalizedPowerW: null,
    energyKj: 0,
    powerTime: Duration.zero,
    heartRateTime: Duration.zero,
    heartRateBeatSeconds: 0,
    metHours: 0,
    heartRateZones: <Duration>[
      Duration.zero,
      Duration.zero,
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ],
    powerZones: <Duration>[
      Duration.zero,
      Duration.zero,
      Duration.zero,
      Duration.zero,
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ],
    estimatedEnergyKj: 0,
    estimatedPowerTime: Duration.zero,
  );

  /// How many zones [heartRateZones] has.
  static const int zoneCount = 5;

  /// Time spent moving, the denominator of every coverage ratio.
  final Duration movingTime;

  /// The highest cadence a sensor reported while moving; `null` without one.
  final int? maxCadenceRpm;

  /// The highest power a meter reported while moving; `null` without one.
  final int? maxPowerW;

  /// The meter's readings as [normalizedPower] weighs them, over the moving
  /// legs; `null` without a meter or with under half a minute of it. From
  /// readings only, never from the estimate.
  final int? normalizedPowerW;

  /// Work done in kilojoules: the mean power of every leg whose both ends
  /// carried a reading, times its duration.
  final double energyKj;

  /// How long the power meter reported for, the sum of those legs.
  final Duration powerTime;

  /// How long a heart rate was known for: the legs whose start carried one.
  final Duration heartRateTime;

  /// Heart rate times seconds over those legs, so that
  /// `heartRateBeatSeconds / heartRateTime` is the mean heart rate.
  final double heartRateBeatSeconds;

  /// The ACSM metabolic equivalent of every leg's speed, times its hours.
  final double metHours;

  /// Time in each of the [zoneCount] heart-rate zones, all zero unless the
  /// analysis was given a maximum heart rate to cut them at.
  final List<Duration> heartRateZones;

  /// Time in each of the [powerZoneCount] power zones, all zero unless the
  /// analysis was given a threshold power to cut them at.
  final List<Duration> powerZones;

  /// Work done in kilojoules as the power model prices it, from speed, slope
  /// and mass alone; zero unless the analysis was given a [PowerModel].
  final double estimatedEnergyKj;

  /// How long the model could price: the moving legs long enough and slow
  /// enough to believe.
  final Duration estimatedPowerTime;

  /// The mean estimated power in watts, or `null` without a model or a leg
  /// it could price. An estimate, never a reading.
  int? get estimatedAvgPowerW {
    final seconds =
        estimatedPowerTime.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return null;
    return (estimatedEnergyKj * 1000 / seconds).round();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideEffort &&
          other.movingTime == movingTime &&
          other.maxCadenceRpm == maxCadenceRpm &&
          other.maxPowerW == maxPowerW &&
          other.normalizedPowerW == normalizedPowerW &&
          other.energyKj == energyKj &&
          other.powerTime == powerTime &&
          other.heartRateTime == heartRateTime &&
          other.heartRateBeatSeconds == heartRateBeatSeconds &&
          other.metHours == metHours &&
          other.estimatedEnergyKj == estimatedEnergyKj &&
          other.estimatedPowerTime == estimatedPowerTime &&
          _sameZones(other.heartRateZones, heartRateZones) &&
          _sameZones(other.powerZones, powerZones);

  static bool _sameZones(List<Duration> a, List<Duration> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    movingTime,
    maxCadenceRpm,
    maxPowerW,
    normalizedPowerW,
    energyKj,
    powerTime,
    heartRateTime,
    heartRateBeatSeconds,
    metHours,
    Object.hashAll(heartRateZones),
    Object.hashAll(powerZones),
    estimatedEnergyKj,
    estimatedPowerTime,
  );

  @override
  String toString() =>
      'RideEffort(moving $movingTime, max ${maxCadenceRpm ?? '-'} rpm, '
      'max ${maxPowerW ?? '-'} W, norm. ${normalizedPowerW ?? '-'} W, '
      '${energyKj.toStringAsFixed(0)} kJ over '
      '$powerTime, HR over $heartRateTime, '
      '${metHours.toStringAsFixed(2)} MET·h, zones $heartRateZones, '
      'power zones $powerZones, '
      'est. ${estimatedEnergyKj.toStringAsFixed(0)} kJ over '
      '$estimatedPowerTime)';
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
    this.effort = RideEffort.zero,
    this.climbs = const <RideClimb>[],
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

  /// How hard the ride was: the sums a calorie estimate and the heart-rate
  /// zones are built from.
  final RideEffort effort;

  /// The climbs, in riding order; empty on a ride without one worth listing.
  final List<RideClimb> climbs;

  /// Whether there is an elevation chart to draw.
  bool get hasElevation =>
      _spansDistance && samples.where((s) => s.elevationM != null).length >= 2;

  /// Whether there is a speed chart to draw.
  bool get hasSpeed => _spansDistance && samples.any((s) => s.speedMps > 0);

  /// Whether there is a heart rate chart to draw.
  bool get hasHeartRate =>
      _spansDistance &&
      samples.where((s) => s.heartRateBpm != null).length >= 2;

  bool get _spansDistance => samples.length >= 2 && samples.last.distanceM > 0;

  @override
  String toString() =>
      'RideAnalysis(${splits.length} splits, ${samples.length} samples, '
      '$speedBands, ${climbs.length} climbs)';
}

/// Measures [points] for the ride page.
///
/// [splitLengthM] is a kilometre or a mile, [breaks] the stretches the
/// recorder was switched off in — the same ones [computeRideStats] is given,
/// so the splits add up to the figures above them. Fixes are accepted and
/// rejected exactly as [RideStatsAccumulator] does it, which is what keeps the
/// two from disagreeing.
///
/// [maxHeartRateBpm] is the rider's maximum, which cuts the heart-rate zones;
/// without it the zones stay empty. [thresholdPowerW] is the rider's
/// threshold power, which cuts the power zones the same way. [powerModel] is
/// the rider and bike the power estimate is made for; without it nothing is
/// estimated.
RideAnalysis analyseRide(
  List<TrackPoint> points, {
  double splitLengthM = metersPerKilometer,
  List<StatsBreak> breaks = const <StatsBreak>[],
  Duration pauseGap = statsPauseGap,
  int maxSamples = rideChartMaxSamples,
  double hysteresisM = elevationHysteresisM,
  int? maxHeartRateBpm,
  int? thresholdPowerW,
  PowerModel? powerModel,
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
  // One smoothing serves the power estimate's grades and the climbs.
  final smoothedElevation = _smoothedElevations(walk);
  return RideAnalysis(
    splits: _splits(walk, splitLengthM: splitLengthM, hysteresisM: hysteresisM),
    samples: _samples(walk, maxSamples: maxSamples),
    speedBands: _speedBands(walk),
    splitLengthM: splitLengthM,
    effort: _effort(
      walk,
      smoothedElevation: smoothedElevation,
      maxHeartRateBpm: maxHeartRateBpm,
      thresholdPowerW: thresholdPowerW,
      powerModel: powerModel,
    ),
    climbs: detectClimbs(_climbLegs(walk, smoothedElevation)),
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
  _RawSample(this.distanceM, this.elevationM, this.speedMps, this.heartRateBpm);

  final double distanceM;
  double? elevationM;
  double speedMps;
  final int? heartRateBpm;
}

List<ChartSample> _samples(_Walk walk, {required int maxSamples}) {
  if (walk.firstIndex < 0) return const <ChartSample>[];
  final raw = <_RawSample>[
    _RawSample(
      0,
      _finite(walk.points[walk.firstIndex].ele),
      0,
      walk.points[walk.firstIndex].heartRateBpm,
    ),
    for (final leg in walk.legs)
      _RawSample(
        walk.distanceAt[leg.toIndex],
        _finite(walk.points[leg.toIndex].ele),
        leg.isBreak ? 0 : leg.speedMps,
        walk.points[leg.toIndex].heartRateBpm,
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
    heartRateBpm: s.heartRateBpm,
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
        heartRateBpm: _lerpOrNull(
          a.heartRateBpm?.toDouble(),
          b.heartRateBpm?.toDouble(),
          f,
        )?.round(),
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

// ----------------------------------------------------------------- effort

/// The ACSM compendium's metabolic equivalents for cycling, by speed in km/h:
/// under 16 is leisure, 16–19 light, 19–22.5 moderate, 22.5–25.7 vigorous,
/// 25.7–30.6 racing, and above that very fast racing.
double _metOf(double speedMps) {
  final kmh = speedMps * 3.6;
  if (kmh < 16) return 4.0;
  if (kmh < 19) return 6.8;
  if (kmh < 22.5) return 8.0;
  if (kmh < 25.7) return 10.0;
  if (kmh <= 30.6) return 12.0;
  return 15.8;
}

/// The zone of a heart rate as a share of [max]: below 60 % is zone 1, then
/// one zone per ten points up to 90 % and above, zone 5. Integer arithmetic,
/// so a reading exactly on a boundary lands where the boundary says.
int _zoneOf(int bpm, int max) {
  final tenths = bpm * 10;
  if (tenths < 6 * max) return 0;
  if (tenths < 7 * max) return 1;
  if (tenths < 8 * max) return 2;
  if (tenths < 9 * max) return 3;
  return 4;
}

RideEffort _effort(
  _Walk walk, {
  required List<double?> smoothedElevation,
  required int? maxHeartRateBpm,
  required int? thresholdPowerW,
  required PowerModel? powerModel,
}) {
  var movingMicros = 0;
  int? maxCadence;
  int? maxPower;
  var energyKj = 0.0;
  var powerMicros = 0;
  var heartRateMicros = 0;
  var beatSeconds = 0.0;
  var metHours = 0.0;
  final zoneMicros = List<int>.filled(RideEffort.zoneCount, 0);
  final powerZoneMicros = List<int>.filled(powerZoneCount, 0);
  var estimatedKj = 0.0;
  var estimatedMicros = 0;
  // The meter's readings in time order for the normalised power, each fix
  // once: consecutive legs share the fix between them.
  final powerSamples = <PowerSample>[];
  DateTime? powerOrigin;
  int? lastPowerSecond;
  void samplePower(TrackPoint point) {
    final watts = point.powerW;
    final time = point.time;
    if (watts == null || time == null) return;
    powerOrigin ??= time;
    final second = time.difference(powerOrigin!).inSeconds;
    if (second == lastPowerSecond) return;
    lastPowerSecond = second;
    powerSamples.add((atSeconds: second, watts: watts));
  }

  // The speed of the leg before, for the acceleration; `null` at the start,
  // after a break and after a leg that was not moving: a rider standing at a
  // light whose fixes jitter a few metres would otherwise be charged a
  // kilowatt of "acceleration" for a second, and the model cannot tell that
  // from setting off. Setting off is priced from the second moving leg on.
  double? previousSpeed;

  for (final leg in walk.legs) {
    if (leg.isBreak) {
      previousSpeed = null;
      continue;
    }
    final micros = leg.duration.inMicroseconds;
    final seconds = micros / Duration.microsecondsPerSecond;
    // Metres over seconds, not the receiver's own figure: the model prices
    // the ground that was covered.
    final measuredSpeed = seconds <= 0 ? 0.0 : leg.meters / seconds;
    final acceleration = previousSpeed == null || seconds <= 0
        ? 0.0
        : (measuredSpeed - previousSpeed) / seconds;
    previousSpeed = leg.moving ? measuredSpeed : null;
    if (!leg.moving) continue;
    final from = walk.points[leg.fromIndex];
    final to = walk.points[leg.toIndex];
    movingMicros += micros;

    if (powerModel != null &&
        seconds >= 1 &&
        measuredSpeed <= maxPlausibleSpeedMps) {
      final startM = smoothedElevation[leg.fromIndex];
      final endM = smoothedElevation[leg.toIndex];
      final grade = startM != null && endM != null && leg.meters > 0
          ? ((endM - startM) / leg.meters).clamp(
              -powerGradeLimit,
              powerGradeLimit,
            )
          : 0.0;
      final elevationM = startM != null && endM != null
          ? (startM + endM) / 2
          : startM ?? endM ?? 0.0;
      final watts = pedalPowerW(
        powerModel,
        vMps: measuredSpeed,
        grade: grade,
        aMps2: acceleration,
        elevationM: elevationM,
      );
      estimatedKj += watts * seconds / 1000;
      estimatedMicros += micros;
    }

    for (final point in <TrackPoint>[from, to]) {
      final cadence = point.cadenceRpm;
      if (cadence != null && (maxCadence == null || cadence > maxCadence)) {
        maxCadence = cadence;
      }
      final power = point.powerW;
      if (power != null && (maxPower == null || power > maxPower)) {
        maxPower = power;
      }
    }

    final powerFrom = from.powerW;
    final powerTo = to.powerW;
    if (powerFrom != null && powerTo != null) {
      energyKj += (powerFrom + powerTo) / 2 * seconds / 1000;
      powerMicros += micros;
    }
    if (powerFrom != null && thresholdPowerW != null && thresholdPowerW > 0) {
      powerZoneMicros[powerZoneOf(powerFrom, thresholdPowerW)] += micros;
    }
    samplePower(from);
    samplePower(to);

    final bpm = from.heartRateBpm;
    if (bpm != null) {
      heartRateMicros += micros;
      beatSeconds += bpm * seconds;
      if (maxHeartRateBpm != null && maxHeartRateBpm > 0) {
        zoneMicros[_zoneOf(bpm, maxHeartRateBpm)] += micros;
      }
    }

    metHours += _metOf(leg.speedMps) * seconds / Duration.secondsPerHour;
  }

  return RideEffort(
    movingTime: Duration(microseconds: movingMicros),
    maxCadenceRpm: maxCadence,
    maxPowerW: maxPower,
    normalizedPowerW: normalizedPower(powerSamples),
    energyKj: energyKj,
    powerTime: Duration(microseconds: powerMicros),
    heartRateTime: Duration(microseconds: heartRateMicros),
    heartRateBeatSeconds: beatSeconds,
    metHours: metHours,
    heartRateZones: List<Duration>.unmodifiable(<Duration>[
      for (final micros in zoneMicros) Duration(microseconds: micros),
    ]),
    powerZones: List<Duration>.unmodifiable(<Duration>[
      for (final micros in powerZoneMicros) Duration(microseconds: micros),
    ]),
    estimatedEnergyKj: estimatedKj,
    estimatedPowerTime: Duration(microseconds: estimatedMicros),
  );
}

/// The height of every accepted fix as the mean of all accepted fixes within
/// [powerGradeSmoothingM] of track distance before and after it, inclusive;
/// `null` where none of them carried a height. Indexed like [_Walk.points];
/// a rejected fix stays `null`.
List<double?> _smoothedElevations(_Walk walk) {
  final out = List<double?>.filled(walk.points.length, null);
  if (walk.firstIndex < 0) return out;
  final accepted = <int>[
    walk.firstIndex,
    for (final leg in walk.legs) leg.toIndex,
  ];
  // Both ends of the window only ever move forward, since the distance
  // along the accepted fixes never decreases.
  var lo = 0;
  var hi = -1;
  var sum = 0.0;
  var count = 0;
  for (var k = 0; k < accepted.length; k++) {
    final here = walk.distanceAt[accepted[k]];
    while (hi + 1 < accepted.length &&
        walk.distanceAt[accepted[hi + 1]] - here <= powerGradeSmoothingM) {
      hi++;
      final ele = _finite(walk.points[accepted[hi]].ele);
      if (ele != null) {
        sum += ele;
        count++;
      }
    }
    while (lo < k &&
        here - walk.distanceAt[accepted[lo]] > powerGradeSmoothingM) {
      final ele = _finite(walk.points[accepted[lo]].ele);
      if (ele != null) {
        sum -= ele;
        count--;
      }
      lo++;
    }
    out[accepted[k]] = count == 0 ? null : sum / count;
  }
  return out;
}

// ----------------------------------------------------------------- climbs

/// The accepted steps as [detectClimbs] reads them, at the smoothed heights
/// the power estimate uses too, so a GPS wobble is a grade for neither.
List<ClimbLeg> _climbLegs(_Walk walk, List<double?> smoothedElevation) =>
    <ClimbLeg>[
      for (final leg in walk.legs)
        ClimbLeg(
          fromM: walk.distanceAt[leg.fromIndex],
          toM: walk.distanceAt[leg.toIndex],
          fromEle: smoothedElevation[leg.fromIndex],
          toEle: smoothedElevation[leg.toIndex],
          duration: leg.duration,
          moving: leg.moving,
          isBreak: leg.isBreak,
          heartRateBpm: walk.points[leg.fromIndex].heartRateBpm,
          powerW: walk.points[leg.fromIndex].powerW,
        ),
    ];

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
