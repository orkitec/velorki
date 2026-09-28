/// The places, names and the ride the store screenshots show.
///
/// Everything is on Madeira, inside the `W20_N30` oracle tile that
/// `tool/itest_mirror.sh` serves, so every route here is computed by the
/// on-device router. The ride is not a recording: it is laid along a route the
/// device has just computed, with a speed that follows the gradient and a
/// heart rate that follows the effort, the same on every run.
library;

import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A route the screenshots plan, by its waypoints.
class DemoRoute {
  /// Creates the route.
  const DemoRoute(this.name, this.waypoints);

  /// What the library calls it.
  final String name;

  /// Where it is routed through, start first.
  final List<LatLng> waypoints;
}

/// Avenida do Mar in Funchal: where the rider stands, and where the plan and
/// the ride start.
const LatLng funchal = LatLng(32.6472, -16.9080);

/// The plan the first two shots show, and the newest route in the library.
const DemoRoute featuredRoute = DemoRoute('Funchal – Camacha – Santa Cruz', [
  funchal,
  LatLng(32.6789, -16.8448),
  LatLng(32.6880, -16.7935),
]);

/// The rest of the library, oldest first; [featuredRoute] is saved last so it
/// heads the list.
const List<DemoRoute> libraryRoutes = [
  DemoRoute('Funchal – Câmara de Lobos', [funchal, LatLng(32.6497, -16.9760)]),
  DemoRoute('Machico – Caniçal', [
    LatLng(32.7180, -16.7665),
    LatLng(32.7388, -16.7383),
  ]),
  DemoRoute('Caniço – Santa Cruz', [
    LatLng(32.6505, -16.8448),
    LatLng(32.6880, -16.7935),
  ]),
];

/// Up to Camacha: the route the demo ride is laid along.
const List<LatLng> rideWaypoints = [funchal, LatLng(32.6789, -16.8448)];

/// What the demo ride is called, per language; English for any other.
const Map<String, String> rideNames = {
  'en': 'Up to Camacha',
  'de': 'Hinauf nach Camacha',
};

/// The short ride through Funchal the navigation shot is taken on: from the
/// old town up towards Monte, which has turns within the first few hundred
/// metres.
const List<LatLng> navigationWaypoints = [
  LatLng(32.6497, -16.9118),
  LatLng(32.6676, -16.9047),
];

/// When the demo ride started: half past nine on the phone's clock, whatever
/// its time zone.
final DateTime rideStart = DateTime(2026, 9, 20, 9, 30);

/// Seconds between two points of the demo ride: under the recorder's 30 s
/// gap, so all of it counts as moving, and near what a bike computer logs.
const int _stepS = 4;

/// A ride along [route]: a point every few seconds, the speed set by the
/// gradient, the heart rate following the effort with a lag, and a little
/// noise on both from a fixed seed.
List<TrackPoint> demoRide(RouteResult route, {DateTime? start}) {
  final line = route.geometry;
  if (line.length < 2) return const <TrackPoint>[];
  final along = List<double>.filled(line.length, 0);
  for (var i = 1; i < line.length; i++) {
    along[i] = along[i - 1] + haversineMeters(line[i - 1].pos, line[i].pos);
  }
  final total = along.last;
  final elevations = <double>[];
  var lastEle = line.first.ele ?? 0;
  for (final point in line) {
    lastEle = point.ele ?? lastEle;
    elevations.add(lastEle);
  }

  // The index of the segment that holds [metres], by bisection.
  int segmentAt(double metres) {
    var lo = 0;
    var hi = along.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (along[mid] <= metres) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  double fraction(int i, double metres) {
    final span = along[i + 1] - along[i];
    return span <= 0 ? 0 : (metres - along[i]) / span;
  }

  double eleAt(double metres) {
    final m = metres.clamp(0.0, total);
    final i = segmentAt(m);
    final t = fraction(i, m);
    return elevations[i] + (elevations[i + 1] - elevations[i]) * t;
  }

  LatLng posAt(double metres) {
    final m = metres.clamp(0.0, total);
    final i = segmentAt(m);
    final t = fraction(i, m);
    final a = line[i].pos;
    final b = line[i + 1].pos;
    return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  }

  // The gradient over the 300 m around a point, which is what the legs feel;
  // a point-to-point gradient is mostly elevation-model noise.
  double gradeAt(double metres) {
    final back = math.max(0.0, metres - 150);
    final ahead = math.min(total, metres + 150);
    if (ahead - back < 20) return 0;
    return (eleAt(ahead) - eleAt(back)) / (ahead - back);
  }

  final random = math.Random(20260920);
  final begin = start ?? rideStart;
  final points = <TrackPoint>[];
  var metres = 0.0;
  var seconds = 0;
  var speed = 3.0;
  var heart = 96.0;
  var mood = 0.0;
  while (true) {
    final grade = gradeAt(metres);
    // Level road 25 km/h, a 10 % climb about 11, a descent up to 42; the
    // first kilometre is the town, with lights and traffic.
    final kmh = grade >= 0
        ? 25 / (1 + 12 * grade)
        : math.min(42.0, 25 - 110 * grade);
    mood = (mood * 0.95 + (random.nextDouble() - 0.5) * 0.03).clamp(-0.1, 0.1);
    final town = metres < 1000 ? 0.7 : 1.0;
    final target = kmh / 3.6 * town * (1 + mood);
    // A rider eases into a new pace over a quarter of a minute or so.
    speed += (target - speed) * (1 - math.exp(-_stepS / 14));
    speed = speed.clamp(1.5, 12.0);

    // Effort from the climb and the pace, a slow drift over the hour, and a
    // heart that takes half a minute to follow.
    final effort = math.max(0.0, grade) * 300 + (speed * 3.6 - 20) * 0.3;
    final drift = seconds / 3600 * 6;
    final wanted = (116 + effort + drift).clamp(102.0, 184.0);
    heart += (wanted - heart) * (1 - math.exp(-_stepS / 28));
    final bpm = (heart + (random.nextDouble() - 0.5) * 3).round();

    points.add(
      TrackPoint(
        posAt(metres),
        ele: eleAt(metres),
        time: begin.add(Duration(seconds: seconds)),
        heartRateBpm: bpm,
      ),
    );
    if (metres >= total) break;
    metres = math.min(total, metres + speed * _stepS);
    seconds += _stepS;
  }
  return points;
}
