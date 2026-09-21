import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

import '../../planner/domain/route_poi.dart';

/// A point of interest the ride passed, and how far along the ride it did.
typedef PoiMark = ({double alongM, RoutePoi poi});

/// Where along the ride each of [pois] was passed: the distance of the
/// nearest fix of [points] within [withinM] metres, read off [distanceAt],
/// which has one entry per fix as the ride analysis measures it.
///
/// A point the ride never came within [withinM] of is left out — a route
/// cut short, or a detour around the café. The marks come back in riding
/// order.
List<PoiMark> poiMarks(
  List<RoutePoi> pois,
  List<TrackPoint> points,
  List<double> distanceAt, {
  double withinM = 60,
}) {
  final n = math.min(points.length, distanceAt.length);
  if (n == 0 || pois.isEmpty) return const <PoiMark>[];
  // A degree of latitude is about 111 km; a box this wide around the point
  // spares the haversine for every fix on the other side of town.
  final latMargin = withinM / 111195;
  final marks = <PoiMark>[];
  for (final poi in pois) {
    final lonMargin =
        latMargin / math.max(math.cos(poi.pos.lat * math.pi / 180), 0.01);
    var nearest = -1;
    var best = withinM;
    for (var i = 0; i < n; i++) {
      final pos = points[i].pos;
      if ((pos.lat - poi.pos.lat).abs() > latMargin ||
          (pos.lon - poi.pos.lon).abs() > lonMargin) {
        continue;
      }
      final d = haversineMeters(poi.pos, pos);
      if (d <= best) {
        best = d;
        nearest = i;
      }
    }
    if (nearest >= 0) marks.add((alongM: distanceAt[nearest], poi: poi));
  }
  marks.sort((a, b) => a.alongM.compareTo(b.alongM));
  return marks;
}
