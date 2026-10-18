// Turns for a plain track on the oracle's committed Madeira tile: a route the
// router planned, stripped of its turns, gets them back from the map.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/track_turns.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

const String _tiles = '../tools/brouter-oracle/tiles';
const String _profiles = '../brouter/profiles';

String? get _skip {
  if (!File('$_tiles/W20_N30.rd5').existsSync()) return 'no Madeira tile';
  if (!File('$_profiles/lookups.dat').existsSync()) return 'no lookups.dat';
  return null;
}

const RoutingDecision _covered = RoutingDecision(
  source: RoutingSource.local,
  requiredTiles: <TileName>[],
  missingTiles: <TileName>[],
);

const Timeout _slow = Timeout(Duration(minutes: 3));

void main() {
  late LocalRoutingBackend backend;

  setUpAll(() {
    if (_skip != null) return;
    backend = LocalRoutingBackend(segmentsDir: _tiles, profilesDir: _profiles);
  });

  tearDownAll(() async {
    if (_skip != null) return;
    await backend.dispose();
  });

  test(
    'a planned route through Funchal, as a bare track, gets its turns back '
    'from the map on the points where the router had them',
    () async {
      final planned = await backend.route(
        RouteQuery(
          points: const <LatLng>[
            LatLng(32.6385, -16.9440),
            LatLng(32.6477, -16.9086),
          ],
          profile: RouteProfile.trekking.engineName,
        ),
      );
      final track = planned.geometry;
      final line = planned.positions;
      final along = cumulativeDistancesMeters(line);
      final service = TrackTurnService(
        local: backend,
        decide: (_) => _covered,
        // Small chunks, so the track crosses several chunk boundaries.
        maxPointsPerQuery: 8,
      );

      final generated = await service.generate(points: track);

      expect(generated.state, TrackTurnsState.generated);
      final made = generated.turns
          .where((t) => t.kind != TurnKind.end)
          .toList();
      final real = planned.turns
          .where(
            (t) =>
                t.kind != TurnKind.end &&
                t.kind != TurnKind.straight &&
                t.pointIndex > 0,
          )
          .toList();
      final reason = 'planned $real\ngenerated $made';
      expect(real, isNotEmpty);
      // Every turn of the plan is found within 25 m of where it was, with
      // a kind to the same side.
      var found = 0;
      for (final turn in real) {
        final match = made.where(
          (t) =>
              (along[t.pointIndex] - along[turn.pointIndex]).abs() <= 25 &&
              _side(t.kind) == _side(turn.kind),
        );
        if (match.isNotEmpty) found++;
      }
      expect(found / real.length, greaterThanOrEqualTo(0.8), reason: reason);
      // And hardly anything the plan did not have.
      expect(made.length, lessThanOrEqualTo(real.length + 2), reason: reason);
      // The plan turns round nowhere, and neither do the turns found: a
      // waypoint on the hairpin is no reason to.
      expect(
        made.where(
          (t) =>
              t.kind == TurnKind.uTurn ||
              t.kind == TurnKind.uTurnLeft ||
              t.kind == TurnKind.uTurnRight,
        ),
        isEmpty,
        reason: reason,
      );
      expect(generated.turns.last.kind, TurnKind.end);
      expect(generated.turns.last.pointIndex, line.length - 1);
    },
    timeout: _slow,
    skip: _skip,
  );
}

int _side(TurnKind kind) => switch (kind) {
  TurnKind.left ||
  TurnKind.slightLeft ||
  TurnKind.sharpLeft ||
  TurnKind.keepLeft ||
  TurnKind.uTurnLeft ||
  TurnKind.exitLeft => -1,
  TurnKind.right ||
  TurnKind.slightRight ||
  TurnKind.sharpRight ||
  TurnKind.keepRight ||
  TurnKind.uTurnRight ||
  TurnKind.exitRight => 1,
  _ => 0,
};
