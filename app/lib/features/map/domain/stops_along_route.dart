import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// How far from the route a stop may be and still count as on the way, in
/// metres.
const double stopsCorridorM = 300;

/// How far ahead of the rider the route is searched for stops, in metres.
const double stopsAheadMaxM = 50000;

/// One stop beside the route still ahead: where it meets the route, how far
/// off the route it is, and how far ahead of the rider.
class StopAlongRoute<T> {
  /// Creates the placing.
  const StopAlongRoute({
    required this.stop,
    required this.atM,
    required this.offM,
    required this.aheadM,
  });

  /// The stop itself.
  final T stop;

  /// Where along the route the stop is passed, in metres from its start.
  final double atM;

  /// How far the stop is from the route there, in metres.
  final double offM;

  /// How much route lies between the rider and the stop, in metres.
  final double aheadM;

  /// The same stop seen by a rider [alongM] metres along the route.
  StopAlongRoute<T> seenFrom(double alongM) =>
      StopAlongRoute<T>(stop: stop, atM: atM, offM: offM, aheadM: atM - alongM);

  @override
  String toString() =>
      'StopAlongRoute($stop, ${aheadM.toStringAsFixed(0)} m ahead, '
      '${offM.toStringAsFixed(0)} m off)';
}

/// The [candidates] within [corridorM] of the part of [line] the rider still
/// has to ride, from [alongM] to [maxAheadM] beyond it, nearest ahead first.
///
/// [cumulative] is [line]'s `cumulativeDistances`. Only the route ahead is
/// looked at: a stop beside a stretch already ridden is behind the rider,
/// even when it is in sight, unless the route comes back past it, and then
/// it is placed where the route comes back. A stop the route passes twice
/// ahead is placed where it is passed first.
List<StopAlongRoute<T>> stopsAlongRoute<T>({
  required List<LatLng> line,
  required List<double> cumulative,
  required double alongM,
  required Iterable<T> candidates,
  required LatLng Function(T stop) positionOf,
  double corridorM = stopsCorridorM,
  double maxAheadM = stopsAheadMaxM,
}) {
  if (line.length < 2 || cumulative.length != line.length) {
    return <StopAlongRoute<T>>[];
  }
  final total = cumulative.last;
  final fromM = alongM.clamp(0.0, total);
  final toM = math.min(total, fromM + maxAheadM);
  if (toM <= fromM) return <StopAlongRoute<T>>[];
  // The segments that hold some of [fromM, toM].
  var first = 0;
  while (first < line.length - 2 && cumulative[first + 1] <= fromM) {
    first++;
  }
  var last = first;
  while (last < line.length - 2 && cumulative[last + 1] < toM) {
    last++;
  }
  final segments = <_Segment>[
    for (var i = first; i <= last; i++)
      _Segment(line[i], line[i + 1], cumulative[i], cumulative[i + 1]),
  ];
  // Each segment's box grown by the corridor, so most of the route is ruled
  // out for a stop by four comparisons.
  final dLat = corridorM / _metersPerDegree;
  final placed = <StopAlongRoute<T>>[];
  for (final stop in candidates) {
    final p = positionOf(stop);
    final dLon =
        corridorM /
        (_metersPerDegree * math.max(math.cos(p.lat * math.pi / 180), 1e-6));
    double? bestOff;
    double? bestAt;
    for (final s in segments) {
      final inBox =
          p.lat >= s.south - dLat &&
          p.lat <= s.north + dLat &&
          p.lon >= s.west - dLon &&
          p.lon <= s.east + dLon;
      if (!inBox) {
        // Out of the corridor: the first stretch beside the stop is over.
        if (bestOff != null) break;
        continue;
      }
      final (off, at) = s.project(p, fromM, toM);
      if (off > corridorM) {
        if (bestOff != null) break;
        continue;
      }
      if (bestOff == null || off < bestOff) {
        bestOff = off;
        bestAt = at;
      }
    }
    if (bestOff == null || bestAt == null) continue;
    placed.add(
      StopAlongRoute<T>(
        stop: stop,
        atM: bestAt,
        offM: bestOff,
        aheadM: bestAt - fromM,
      ),
    );
  }
  placed.sort((a, b) => a.aheadM.compareTo(b.aheadM));
  return placed;
}

/// Boxes over the route from [fromM] to [toM] metres along it, each about
/// [chunkM] of route long and grown by [padM]: what the stops beside that
/// stretch are fetched with, one indexed query a box, rather than one box
/// over a whole winding route that would hold half the countryside.
List<BoundingBox> routeChunkBoxes(
  List<LatLng> line,
  List<double> cumulative, {
  required double fromM,
  required double toM,
  double chunkM = 5000,
  double padM = stopsCorridorM,
}) {
  if (line.length < 2 || cumulative.length != line.length || toM <= fromM) {
    return <BoundingBox>[];
  }
  final boxes = <BoundingBox>[];
  var points = <LatLng>[];
  var chunkStart = 0.0;
  for (var i = 0; i < line.length - 1; i++) {
    // Segments wholly behind [fromM] or beyond [toM] are not wanted.
    if (cumulative[i + 1] <= fromM) continue;
    if (cumulative[i] >= toM) break;
    if (points.isEmpty) {
      points = <LatLng>[line[i]];
      chunkStart = cumulative[i];
    }
    points.add(line[i + 1]);
    if (cumulative[i + 1] - chunkStart >= chunkM) {
      boxes.add(BoundingBox.fromPoints(points).expandMeters(padM));
      points = <LatLng>[];
    }
  }
  if (points.isNotEmpty) {
    boxes.add(BoundingBox.fromPoints(points).expandMeters(padM));
  }
  return boxes;
}

const double _metersPerDegree = 111195;

class _Segment {
  _Segment(this.a, this.b, this.startM, this.endM)
    : south = math.min(a.lat, b.lat),
      north = math.max(a.lat, b.lat),
      west = math.min(a.lon, b.lon),
      east = math.max(a.lon, b.lon);

  final LatLng a;
  final LatLng b;
  final double startM;
  final double endM;
  final double south;
  final double north;
  final double west;
  final double east;

  /// How far [p] is from this segment, and where along the route its foot
  /// is, keeping to the part of the segment between [fromM] and [toM].
  (double, double) project(LatLng p, double fromM, double toM) {
    final length = endM - startM;
    final kx = math.cos(a.lat * math.pi / 180);
    final abx = (b.lon - a.lon) * kx;
    final aby = b.lat - a.lat;
    final apx = (p.lon - a.lon) * kx;
    final apy = p.lat - a.lat;
    final lengthSquared = abx * abx + aby * aby;
    var t = lengthSquared == 0 ? 0.0 : (apx * abx + apy * aby) / lengthSquared;
    final tMin = length <= 0 ? 0.0 : ((fromM - startM) / length);
    final tMax = length <= 0 ? 1.0 : ((toM - startM) / length);
    t = t.clamp(math.max(0.0, tMin), math.min(1.0, tMax));
    final foot = LatLng(
      a.lat + (b.lat - a.lat) * t,
      a.lon + (b.lon - a.lon) * t,
    );
    return (haversineMeters(p, foot), startM + length * t);
  }
}
