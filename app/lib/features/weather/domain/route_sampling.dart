import 'dart:math' as math;

import 'package:velorki_api/velorki_api.dart' show WeatherRequestCell;
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// The most cells one `POST /weather` may ask about.
const int maxWeatherCells = 150;

/// The grid the relay is asked on, in degrees: about 2.5 km of latitude.
/// Snapping to it is what keeps a precise position off the wire.
const double weatherGridDeg = 0.025;

/// The steps an altitude is snapped to, in metres.
const int weatherAltitudeStepM = 50;

/// How far either side of a sample the route's heading is measured over.
const double headingBaseM = 200;

/// One point along the route the weather is looked up for.
class RouteWeatherSample {
  /// Creates a sample.
  const RouteWeatherSample({
    required this.distanceM,
    required this.position,
    required this.bearingDeg,
    required this.offset,
    this.elevationM,
  });

  /// How far along the route it lies.
  final double distanceM;

  /// Where it lies.
  final LatLng position;

  /// The route's height there, when the routing data had one.
  final double? elevationM;

  /// The way the route heads there, degrees clockwise from north, measured
  /// over [headingBaseM] either side so a hairpin does not turn the wind.
  final double bearingDeg;

  /// When the rider gets there, counted from the departure.
  final Duration offset;

  @override
  bool operator ==(Object other) =>
      other is RouteWeatherSample &&
      other.distanceM == distanceM &&
      other.position == position &&
      other.elevationM == elevationM &&
      other.bearingDeg == bearingDeg &&
      other.offset == offset;

  @override
  int get hashCode =>
      Object.hash(distanceM, position, elevationM, bearingDeg, offset);

  @override
  String toString() =>
      'RouteWeatherSample(${distanceM.round()} m, $position, '
      '${bearingDeg.round()}°, +$offset)';
}

/// Samples [route] every [spacingM] metres, the start and the end included.
///
/// The time a sample is reached is its distance at [typicalSpeedKmh], the
/// profile's speed the planner's ride time is worked out with; the router's
/// own time model (`route.times`) is not used, so the weather is for the
/// time the sheet says the ride takes. A route so long that the samples would
/// be more than [maxSamples] is sampled more sparsely instead, so its cells
/// fit one request.
List<RouteWeatherSample> sampleRoute(
  RouteResult route, {
  required double typicalSpeedKmh,
  double spacingM = 2000,
  int maxSamples = maxWeatherCells,
}) {
  final geometry = route.geometry;
  if (geometry.isEmpty) return const <RouteWeatherSample>[];
  final line = _Line(route);
  final total = line.length;
  final spacing = math.max(spacingM, total / math.max(1, maxSamples - 1));

  // A sample within a metre of the end is the end.
  final distances = <double>[0];
  for (var k = 1; k * spacing < total - 1; k++) {
    distances.add(k * spacing);
  }
  if (total > 0) distances.add(total);

  return <RouteWeatherSample>[
    for (final d in distances)
      RouteWeatherSample(
        distanceM: d,
        position: line.positionAt(d),
        elevationM: line.elevationAt(d),
        bearingDeg: total > 0
            ? bearingDegrees(
                line.positionAt(math.max(0, d - headingBaseM)),
                line.positionAt(math.min(total, d + headingBaseM)),
              )
            : 0,
        offset: line.offsetAt(d, typicalSpeedKmh),
      ),
  ];
}

/// The route's line with what is needed to look anything up by distance.
class _Line {
  _Line(RouteResult route)
    : points = route.geometry,
      cumulative = cumulativeDistancesMeters(route.positions);

  final List<TrackPoint> points;
  final List<double> cumulative;

  double get length => cumulative.last;

  /// The index `i` of the segment `i → i + 1` that [d] falls on.
  int _segment(double d) {
    var lo = 0;
    var hi = cumulative.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// How far along its segment [d] lies, 0 to 1.
  double _fraction(int i, double d) {
    if (i + 1 >= cumulative.length) return 0;
    final span = cumulative[i + 1] - cumulative[i];
    return span > 0 ? ((d - cumulative[i]) / span).clamp(0.0, 1.0) : 0;
  }

  LatLng positionAt(double d) {
    final i = _segment(d);
    if (i + 1 >= points.length) return points[i].pos;
    final t = _fraction(i, d);
    final a = points[i].pos;
    final b = points[i + 1].pos;
    return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  }

  /// The height at [d], or the nearest one the line has.
  double? elevationAt(double d) {
    final i = _segment(d);
    final a = points[i].ele;
    final b = i + 1 < points.length ? points[i + 1].ele : null;
    if (a != null && b != null) return a + (b - a) * _fraction(i, d);
    if (a != null || b != null) return a ?? b;
    for (var step = 1; step < points.length; step++) {
      final before = i - step >= 0 ? points[i - step].ele : null;
      final after = i + 1 + step < points.length
          ? points[i + 1 + step].ele
          : null;
      if (before != null || after != null) return before ?? after;
    }
    return null;
  }

  Duration offsetAt(double d, double typicalSpeedKmh) {
    final seconds = typicalSpeedKmh > 0
        ? d / 1000 / typicalSpeedKmh * 3600
        : 0.0;
    return Duration(milliseconds: (seconds * 1000).round());
  }
}

/// [value] on the [weatherGridDeg] grid, written with at most three
/// decimals, as the relay requires.
double snapToWeatherGrid(double value) {
  final snapped = (value / weatherGridDeg).round() * weatherGridDeg;
  final rounded = double.parse(snapped.toStringAsFixed(3));
  // Never -0.0, which would go over the wire as "-0.0".
  return rounded == 0 ? 0.0 : rounded;
}

/// The cell [position] lies in, with [elevationM] to the nearest
/// [weatherAltitudeStepM] metres.
WeatherRequestCell snapCell(LatLng position, double? elevationM) =>
    WeatherRequestCell(
      lat: snapToWeatherGrid(position.lat.clamp(-90.0, 90.0)),
      lon: snapToWeatherGrid(position.lon.clamp(-180.0, 180.0)),
      alt: elevationM == null
          ? null
          : ((elevationM / weatherAltitudeStepM).round() * weatherAltitudeStepM)
                .clamp(-500, 9000),
    );

/// The cells a set of samples asks about, and which one answers each sample.
class WeatherCells {
  /// Creates the set.
  const WeatherCells(this.cells, this.sampleToCell);

  /// Each cell once, in the order the samples first reach them.
  final List<WeatherRequestCell> cells;

  /// For sample `i`, the index into [cells] of the cell it lies in.
  final List<int> sampleToCell;
}

/// The cells [samples] lie in, each once.
WeatherCells cellsFor(List<RouteWeatherSample> samples) {
  final index = <WeatherRequestCell, int>{};
  final sampleToCell = <int>[
    for (final s in samples)
      index.putIfAbsent(snapCell(s.position, s.elevationM), () => index.length),
  ];
  return WeatherCells(
    List<WeatherRequestCell>.unmodifiable(index.keys),
    List<int>.unmodifiable(sampleToCell),
  );
}

/// The hours one `POST /weather` asks for.
typedef WeatherWindow = ({DateTime from, int hours});

/// The hours to ask for a ride leaving at [departure] and taking [rideTime].
///
/// It starts at the full UTC hour at or before [departure] and covers the
/// ride plus [sliderSpan], so the rider can move the departure that much
/// later without another request; the minutes [departure] lies into its hour
/// are covered too. Between 1 and 72 hours, the relay's bounds.
WeatherWindow requestWindow(
  DateTime departure,
  Duration rideTime, {
  Duration sliderSpan = const Duration(hours: 12),
}) {
  final from = floorToUtcHour(departure);
  final span = departure.difference(from) + rideTime + sliderSpan;
  final hours = (span.inMicroseconds / Duration.microsecondsPerHour).ceil() + 1;
  return (from: from, hours: hours.clamp(1, 72));
}

/// [time] in UTC, rounded down to its full hour.
DateTime floorToUtcHour(DateTime time) {
  final utc = time.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
}

/// [now] rounded up to the next quarter hour, unless it is on one: the
/// departure the weather assumes until the rider picks another.
DateTime defaultDeparture(DateTime now) {
  const quarter = 15 * Duration.millisecondsPerMinute;
  final ms = now.toUtc().millisecondsSinceEpoch;
  final up = (ms + quarter - 1) ~/ quarter * quarter;
  return DateTime.fromMillisecondsSinceEpoch(up, isUtc: true);
}
