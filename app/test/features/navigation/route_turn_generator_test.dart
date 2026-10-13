import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/navigation/application/route_turn_generator.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart';
import 'support/fake_turns.dart';

void main() {
  late VelorkiDatabase db;
  late RouteRepository routes;
  late TrackFollowingBackend backend;
  late RouteTurnGenerator generator;
  var missing = const <TileName>[];

  setUp(() {
    db = VelorkiDatabase.memory();
    routes = RouteRepository(
      db.routesDao,
      clock: () => DateTime.utc(2026, 10, 12, 9),
    );
    backend = TrackFollowingBackend();
    missing = const <TileName>[];
    generator = RouteTurnGenerator(
      service: () => fakeTurnService(backend, missing: () => missing),
      routes: routes,
    );
  });
  tearDown(() => db.close());

  test('an imported track without turns gets the map\'s, kept with the '
      'route and marked as made from the map', () async {
    final track = leggedTrack();
    final saved = await routes.saveImportedRoute(
      name: 'Plain track',
      points: track,
      source: RouteSource.importedGpx,
    );
    expect(RouteTurnGenerator.needsTurns(saved), isTrue);

    await generator.fillAfterImport(saved);

    final back = (await routes.routeById(saved.id))!;
    expect(back.turnsGenerated, isTrue);
    expect(back.turns.map((t) => (t.pointIndex, t.kind)), [
      (30, TurnKind.right),
      (track.length - 1, TurnKind.end),
    ]);
    expect(back.updatedAt, saved.updatedAt, reason: 'not an edit');
    expect(back.geometryBlob, saved.geometryBlob, reason: 'the line stays');
    expect(RouteTurnGenerator.needsTurns(back), isFalse);
  });

  test('a track that came with turns is left alone', () async {
    final saved = await routes.saveImportedRoute(
      name: 'With cues',
      points: leggedTrack(),
      source: RouteSource.importedGpx,
      turns: const <TurnHint>[
        TurnHint(pointIndex: 30, kind: TurnKind.right, note: 'At the barn'),
      ],
    );

    await generator.fillAfterImport(saved);

    expect(backend.queries, isEmpty);
    final back = (await routes.routeById(saved.id))!;
    expect(back.turnsGenerated, isFalse);
    expect(back.turns.single.note, 'At the barn');
  });

  test('a route planned here is never offered the map\'s turns', () async {
    final saved = await routes.savePlannedRoute(
      name: 'Planned',
      route: syntheticRoute(),
      waypoints: const [],
      options: const RoutingOptions(),
    );
    expect(saved.turns, isEmpty);
    expect(RouteTurnGenerator.needsTurns(saved), isFalse);
  });

  test('after an import, nothing is routed without the tiles', () async {
    missing = const <TileName>[TileName(10, 45)];
    final saved = await routes.saveImportedRoute(
      name: 'Far away',
      points: leggedTrack(),
      source: RouteSource.importedGpx,
    );

    await generator.fillAfterImport(saved);

    expect(backend.queries, isEmpty);
    expect(generator.missingTiles(saved), [const TileName(10, 45)]);
    expect(await generator.generate(saved), RouteTurnsOutcome.noTiles);
    expect((await routes.routeById(saved.id))!.turnsGenerated, isFalse);
  });

  test(
    'turns made for a line the route no longer has are not written',
    () async {
      final saved = await routes.saveImportedRoute(
        name: 'Edited',
        points: leggedTrack(),
        source: RouteSource.importedGpx,
      );
      // Edited in the meantime: another line under the same id.
      await routes.saveImportedRoute(
        id: saved.id,
        name: 'Edited',
        points: leggedTrack(legs: 3),
        source: RouteSource.importedGpx,
      );

      final written = await routes.setGeneratedTurns(saved.id, const <TurnHint>[
        TurnHint(pointIndex: 30, kind: TurnKind.right),
      ], geometryBlob: saved.geometryBlob);

      expect(written, isFalse);
      expect(await generator.generate(saved), RouteTurnsOutcome.unmatched);
      final back = (await routes.routeById(saved.id))!;
      expect(back.turns, isEmpty);
      expect(back.turnsGenerated, isFalse);
    },
  );

  test('one job per route: a second ask shares the first', () async {
    final saved = await routes.saveImportedRoute(
      name: 'Twice',
      points: leggedTrack(),
      source: RouteSource.importedGpx,
    );

    final first = generator.generate(saved);
    final second = generator.generate(saved);

    expect(await first, RouteTurnsOutcome.created);
    expect(await second, RouteTurnsOutcome.created);
    expect(backend.queries, hasLength(1));
  });

  test('the map\'s turns survive a reopen of the database', () async {
    final saved = await routes.saveImportedRoute(
      name: 'Kept',
      points: leggedTrack(),
      source: RouteSource.importedGpx,
    );
    await generator.generate(saved);

    final row = (await db.routesDao.routeById(saved.id))!;
    expect(row.turnsGenerated, isTrue);
    final again = routes.toDomain(row);
    expect(again.turnsGenerated, isTrue);
    expect(again.turns.first.pointIndex, 30);
    // And written back whole, as the undo of a delete does.
    await routes.delete(saved.id);
    await routes.restore(again);
    expect((await routes.routeById(saved.id))!.turnsGenerated, isTrue);
  });

  test('lacksTurns: only the finish is no turns at all', () {
    expect(lacksTurns(const <TurnHint>[]), isTrue);
    expect(
      lacksTurns(const <TurnHint>[TurnHint(pointIndex: 9, kind: TurnKind.end)]),
      isTrue,
    );
    expect(
      lacksTurns(const <TurnHint>[
        TurnHint(pointIndex: 3, kind: TurnKind.left),
      ]),
      isFalse,
    );
  });

  test('the track is not changed by the turns', () async {
    final track = leggedTrack();
    final saved = await routes.saveImportedRoute(
      name: 'Line',
      points: track,
      source: RouteSource.importedGpx,
    );
    await generator.generate(saved);
    final back = (await routes.routeById(saved.id))!;
    expect(back.geometry.map((p) => p.pos), track.map((p) => p.pos));
    expect(back.distanceM, saved.distanceM);
    expect(back.geometry.first.pos, const LatLng(48, 11));
  });
}
