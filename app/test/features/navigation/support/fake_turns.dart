import 'package:velorki/core/geo/track_turns.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A router that goes exactly through the points it is given and names a
/// turn at every one where the line bends by more than 30°: a stand-in for
/// the on-device engine on a map whose streets are the track's.
class TrackFollowingBackend implements RoutingBackend {
  /// Every query that arrived, in order.
  final List<RouteQuery> queries = <RouteQuery>[];

  /// Fails the queries whose points include any of these.
  final Set<LatLng> failAt = <LatLng>{};

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    queries.add(q);
    if (q.points.any(failAt.contains)) {
      throw const RoutingException(
        kind: RoutingErrorKind.noRoute,
        message: 'no way here',
      );
    }
    final points = q.points;
    final turns = <TurnHint>[];
    for (var i = 1; i < points.length - 1; i++) {
      final into = bearingDegrees(points[i - 1], points[i]);
      final out = bearingDegrees(points[i], points[i + 1]);
      var bend = (out - into) % 360;
      if (bend > 180) bend -= 360;
      if (bend.abs() <= 30) continue;
      turns.add(
        TurnHint(
          pointIndex: i,
          kind: bend < 0 ? TurnKind.left : TurnKind.right,
          angleDeg: bend,
        ),
      );
    }
    turns.add(TurnHint(pointIndex: points.length - 1, kind: TurnKind.end));
    return RouteResult(
      geometry: [for (final p in points) TrackPoint(p)],
      lengthM: polylineLengthMeters(points),
      ascentM: 0,
      descentM: 0,
      messages: const <SegmentMessage>[],
      raw: const <String, dynamic>{},
      turns: turns,
    );
  }
}

/// A turn service over [backend] whose coverage check reports [missing].
TrackTurnService fakeTurnService(
  RoutingBackend backend, {
  List<TileName> Function()? missing,
  int maxPointsPerQuery = 50,
}) => TrackTurnService(
  local: backend,
  maxPointsPerQuery: maxPointsPerQuery,
  decide: (_) => RoutingDecision(
    source: RoutingSource.local,
    requiredTiles: const <TileName>[],
    missingTiles: missing?.call() ?? const <TileName>[],
  ),
);

/// A track from [start]: [legs] straight stretches of [legM] metres each,
/// the first due north and every next one turned by [turnDeg] (positive to
/// the right), a point every [stepM] metres.
List<TrackPoint> leggedTrack({
  LatLng start = const LatLng(48.0, 11.0),
  int legs = 2,
  double legM = 600,
  double turnDeg = 90,
  double stepM = 20,
}) {
  final out = <TrackPoint>[TrackPoint(start)];
  var here = start;
  var heading = 0.0;
  for (var leg = 0; leg < legs; leg++) {
    for (var m = stepM; m <= legM + 1e-6; m += stepM) {
      here = destinationPoint(here, heading, stepM);
      out.add(TrackPoint(here));
    }
    heading = (heading + turnDeg) % 360;
  }
  return out;
}
