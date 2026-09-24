import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'route_poi.dart';
import 'shape_points.dart';
import 'waypoint.dart';

/// A point of interest nearer than this to the track is on it.
const double poiOnTrackM = 30;

/// The waypoints a route that was not planned here opens with in the
/// planner: its ends, the points of interest that lie on its track as named
/// waypoints where the track passes them, and shape points between those
/// so the course is kept.
///
/// A GPX file's `<wpt>` elements are stored as the route's [pois]; the
/// ones on the track are what the author put along the way, and they come
/// along with their name, kind and description as a point's note. Those
/// farther off the track are left as they are: a waypoint there would pull
/// a re-route off the course to visit it. A point within [poiOnTrackM] of
/// the start or the end names that end rather than adding a point beside
/// it.
///
/// [maxVia] caps the points between the ends, but a named point is never
/// dropped for it: with more named points than the cap, the cap grows to
/// fit them and the shape points go.
List<Waypoint> routeWaypoints({
  required List<LatLng> track,
  required List<Waypoint> saved,
  List<RoutePoi> pois = const <RoutePoi>[],
  List<TurnHint> turns = const <TurnHint>[],
  double onTrackM = poiOnTrackM,
  int maxVia = maxShapePoints,
}) {
  if (track.length <= 2) return saved;
  var start = saved.isNotEmpty
      ? saved.first
      : Waypoint(pos: track.first, kind: WaypointKind.start);
  var end = saved.length > 1
      ? saved.last
      : Waypoint(pos: track.last, kind: WaypointKind.end);
  final cumulative = cumulativeDistancesMeters(track);
  final lengthM = cumulative.last;

  // The points of interest on the track, each with where along it it lies.
  final named = <(double, Waypoint)>[];
  for (final poi in pois) {
    final on = _project(track, poi.pos, cumulative);
    if (on.distanceM > onTrackM) continue;
    if (on.alongM <= onTrackM) {
      start = _named(start, poi);
      continue;
    }
    if (lengthM - on.alongM <= onTrackM) {
      end = _named(end, poi);
      continue;
    }
    named.add((on.alongM, _named(Waypoint(pos: on.snapped), poi)));
  }
  // The cue sheet's own turns, the ones an author wrote, as points of the
  // turn kind, so they can be read and changed in the waypoint sheet. The
  // router's unnamed turns stay in the route's turns; a point for each
  // would bury the plan.
  for (final turn in turns) {
    if (turn.note == null || turn.note!.isEmpty) continue;
    if (turn.pointIndex <= 0 || turn.pointIndex >= track.length - 1) continue;
    if (turn.kind == TurnKind.end) continue;
    named.add((
      cumulative[turn.pointIndex],
      Waypoint(
        pos: track[turn.pointIndex],
        name: turn.note,
        poiKind: PoiKind.turn,
        turn: turn.kind,
      ),
    ));
  }
  named.sort((a, b) => a.$1.compareTo(b.$1));

  // Shape points fill what is left of the cap, and one that sits where a
  // named point already is would only be that point twice.
  final room = math.max(0, maxVia - named.length);
  final shape = <(double, Waypoint)>[
    for (final i in shapePointIndices(track, maxVia: room))
      if (i > 0 && i < track.length - 1)
        if (!named.any((n) => (n.$1 - cumulative[i]).abs() <= onTrackM))
          (cumulative[i], Waypoint(pos: track[i])),
  ];
  final between = <(double, Waypoint)>[...named, ...shape]
    ..sort((a, b) => a.$1.compareTo(b.$1));
  return <Waypoint>[start, for (final entry in between) entry.$2, end];
}

/// [point] carrying what [poi] says: its name, kind and description.
Waypoint _named(Waypoint point, RoutePoi poi) => point.copyWith(
  name: poi.name.isEmpty ? point.name : poi.name,
  poiKind: poi.kind,
  note: poi.description?.isEmpty ?? true ? point.note : poi.description,
);

/// Where a point falls on a track: how far off it is, how far along the
/// track that is, and the point of the track it maps to.
class TrackProjection {
  /// Creates a projection.
  const TrackProjection(this.distanceM, this.alongM, this.snapped);

  /// How far the point lies off the track.
  final double distanceM;

  /// How far along the track the nearest place is.
  final double alongM;

  /// That place on the track.
  final LatLng snapped;
}

/// Where [point] is nearest to [track]: how far off, how far along, and
/// the point of the track it maps to. Flat-earth segment maths, exact
/// enough for the tens of metres that matter here.
///
/// [cumulative] is [cumulativeDistancesMeters] of the same track, computed
/// here when the caller has none to hand.
TrackProjection projectOnTrack(
  List<LatLng> track,
  LatLng point, {
  List<double>? cumulative,
}) => _project(track, point, cumulative ?? cumulativeDistancesMeters(track));

TrackProjection _project(
  List<LatLng> track,
  LatLng point,
  List<double> cumulative,
) {
  var best = const TrackProjection(double.infinity, 0, LatLng(0, 0));
  for (var i = 0; i < track.length - 1; i++) {
    final a = track[i];
    final b = track[i + 1];
    final kx = math.cos(a.latRad);
    final abx = (b.lon - a.lon) * kx;
    final aby = b.lat - a.lat;
    final apx = (point.lon - a.lon) * kx;
    final apy = point.lat - a.lat;
    final lengthSq = abx * abx + aby * aby;
    final t = lengthSq == 0
        ? 0.0
        : ((apx * abx + apy * aby) / lengthSq).clamp(0.0, 1.0);
    final snapped = LatLng(a.lat + t * aby, a.lon + t * abx / kx);
    final distance = haversineMeters(point, snapped);
    if (distance < best.distanceM) {
      best = TrackProjection(
        distance,
        cumulative[i] + t * (cumulative[i + 1] - cumulative[i]),
        snapped,
      );
    }
  }
  return best;
}

/// The points of interest of [pois] that do not lie on [track]: what a plan
/// carries as points beside the route, since routing through one would pull
/// the route off its course to visit it.
///
/// The mirror image of what [routeWaypoints] takes: together the two sets
/// are every point the file came with, once each.
List<RoutePoi> besideTrackPois({
  required List<LatLng> track,
  required List<RoutePoi> pois,
  double onTrackM = poiOnTrackM,
}) {
  if (pois.isEmpty) return const <RoutePoi>[];
  if (track.length <= 2) return pois;
  final cumulative = cumulativeDistancesMeters(track);
  return <RoutePoi>[
    for (final poi in pois)
      if (projectOnTrack(track, poi.pos, cumulative: cumulative).distanceM >
          onTrackM)
        poi,
  ];
}

/// Where a point beside the route belongs in [waypoints] once the route is
/// routed through it: before the first waypoint that lies further along
/// [track] than it does.
///
/// Always a via: a point picked up beside the route neither starts nor ends
/// the ride, whatever end of the track it sits near.
int viaIndexAlongTrack({
  required List<LatLng> track,
  required List<Waypoint> waypoints,
  required LatLng pos,
}) {
  if (waypoints.length < 2) return waypoints.length;
  if (track.length < 2) return waypoints.length - 1;
  final cumulative = cumulativeDistancesMeters(track);
  final along = projectOnTrack(track, pos, cumulative: cumulative).alongM;
  for (var i = 1; i < waypoints.length; i++) {
    final at = projectOnTrack(
      track,
      waypoints[i].pos,
      cumulative: cumulative,
    ).alongM;
    if (at >= along) return i;
  }
  return waypoints.length - 1;
}
