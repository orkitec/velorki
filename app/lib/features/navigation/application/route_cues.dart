import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../planner/domain/route_poi.dart';
import 'navigation_controller.dart';
import 'route_geometry.dart';

part 'route_cues.g.dart';

/// One line of the cue sheet: a turn, a point of interest or the finish,
/// and how far along the route it sits.
@immutable
class RouteCue {
  /// Creates a cue at [alongM].
  const RouteCue({required this.alongM, this.turn, this.poi});

  /// Distance from the start of the route, in metres.
  final double alongM;

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
  if (route == null || route.line.length < 2) return const <RouteCue>[];
  final cumulative = cumulativeDistances(route.line);
  final cues = <RouteCue>[];
  for (final turn in route.turns) {
    // Carrying on straight is not a line on a cue sheet, unless the author
    // wrote something for it.
    final silent =
        (turn.kind == TurnKind.straight ||
            turn.kind == TurnKind.beeline ||
            turn.kind == TurnKind.offRoad) &&
        (turn.note == null || turn.note!.isEmpty);
    if (silent) continue;
    if (turn.pointIndex < 0 || turn.pointIndex >= cumulative.length) continue;
    cues.add(RouteCue(alongM: cumulative[turn.pointIndex], turn: turn));
  }
  for (final poi in route.pois) {
    final on = projectOnLine(route.line, poi.pos, cumulative: cumulative);
    if (on.distanceM > poiBesideRouteM) continue;
    cues.add(RouteCue(alongM: on.alongM, poi: poi));
  }
  if (!cues.any((c) => c.isFinish)) {
    cues.add(
      RouteCue(
        alongM: cumulative.last,
        turn: TurnHint(pointIndex: route.line.length - 1, kind: TurnKind.end),
      ),
    );
  }
  cues.sort((a, b) => a.alongM.compareTo(b.alongM));
  return List<RouteCue>.unmodifiable(cues);
}
