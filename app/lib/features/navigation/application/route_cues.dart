import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../planner/domain/route_poi.dart';
import 'navigation_controller.dart';
import 'route_geometry.dart';

part 'route_cues.g.dart';

/// One line of the cue sheet: a turn, a point of interest or the finish,
/// and how far along the route it sits.
@immutable
class RouteCue {
  /// Creates a cue at [alongM].
  const RouteCue({
    required this.alongM,
    required this.pos,
    this.turn,
    this.poi,
    this.turnIndex,
    this.poiIndex,
  });

  /// Distance from the start of the route, in metres.
  final double alongM;

  /// Where it is, for a map to go to.
  final LatLng pos;

  /// Index into the route's turns, for a turn.
  final int? turnIndex;

  /// Index into the route's points of interest, for one.
  final int? poiIndex;

  /// The turn, for a turn or the finish.
  final TurnHint? turn;

  /// The point of interest, for one.
  final RoutePoi? poi;

  /// Whether this is the end of the route.
  bool get isFinish => turn?.kind == TurnKind.end;
}

/// The guided route's cue sheet, in route order: every turn worth a line,
/// every point of interest on the route, and the finish.
///
/// Computed once per route, not per fix: the sheet's page takes the rider's
/// distance along the route off the progress and does the subtraction.
@Riverpod(keepAlive: true)
List<RouteCue> guidedRouteCues(Ref ref) {
  final route = ref.watch(activeGuidedRouteProvider);
  if (route == null) return const <RouteCue>[];
  return routeCuesFor(route.line, turns: route.turns, pois: route.pois);
}

/// The cue sheet of a route given as its [line], its [turns] and its [pois]:
/// every turn worth a line, every point of interest on the route, and the
/// finish, in route order. The same list serves the record sheet, the import
/// preview and the route page.
List<RouteCue> routeCuesFor(
  List<LatLng> line, {
  List<TurnHint> turns = const <TurnHint>[],
  List<RoutePoi> pois = const <RoutePoi>[],
}) {
  if (line.length < 2) return const <RouteCue>[];
  final cumulative = cumulativeDistances(line);
  final cues = <RouteCue>[];
  for (var i = 0; i < turns.length; i++) {
    final turn = turns[i];
    // Carrying on straight is not a line on a cue sheet, unless the author
    // wrote something for it.
    final silent =
        (turn.kind == TurnKind.straight ||
            turn.kind == TurnKind.beeline ||
            turn.kind == TurnKind.offRoad) &&
        (turn.note == null || turn.note!.isEmpty);
    if (silent) continue;
    if (turn.pointIndex < 0 || turn.pointIndex >= cumulative.length) continue;
    cues.add(
      RouteCue(
        alongM: cumulative[turn.pointIndex],
        pos: line[turn.pointIndex],
        turn: turn,
        turnIndex: i,
      ),
    );
  }
  for (var i = 0; i < pois.length; i++) {
    final poi = pois[i];
    final on = projectOnLine(line, poi.pos, cumulative: cumulative);
    if (on.distanceM > poiBesideRouteM) continue;
    cues.add(RouteCue(alongM: on.alongM, pos: poi.pos, poi: poi, poiIndex: i));
  }
  if (!cues.any((c) => c.isFinish)) {
    cues.add(
      RouteCue(
        alongM: cumulative.last,
        pos: line.last,
        turn: TurnHint(pointIndex: line.length - 1, kind: TurnKind.end),
      ),
    );
  }
  cues.sort((a, b) => a.alongM.compareTo(b.alongM));
  return List<RouteCue>.unmodifiable(cues);
}
