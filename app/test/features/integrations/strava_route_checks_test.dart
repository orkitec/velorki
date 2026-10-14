import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/integrations/application/strava_route_checks.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/strava/data/strava_client.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart' show syntheticRoute;
import 'support/fake_dio.dart';

final List<TrackPoint> _track = <TrackPoint>[
  for (var i = 0; i < 5; i++) TrackPoint(LatLng(48 + i * 0.001, 11), ele: 500),
];

void main() {
  late VelorkiDatabase db;
  late DateTime now;
  late RouteRepository routes;

  setUp(() {
    db = VelorkiDatabase.memory();
    now = DateTime.utc(2026, 10, 1, 12);
    routes = RouteRepository(db.routesDao, clock: () => now);
  });
  tearDown(() => db.close());

  /// A route imported from Strava now, as Strava route [stravaId].
  Future<String> imported(
    String stravaId, {
    String name = 'From Strava',
  }) async {
    final saved = await routes.saveImportedRoute(
      name: name,
      points: _track,
      source: RouteSource.strava,
    );
    await routes.markExternal(
      saved.id,
      externalIds: <String, Object?>{'strava_route_id': stravaId},
      fetchedAt: now,
    );
    return saved.id;
  }

  StravaRouteChecks checks(StravaRouteProbe? probe) =>
      StravaRouteChecks(db.routesDao, probe, clock: () => now);

  Future<DateTime?> fetchedAt(String id) async =>
      (await db.routesDao.routeById(id))?.externalFetchedAt;

  test('nothing is asked within 48 hours of the import', () async {
    await imported('1');
    final asked = <String>[];
    now = now.add(const Duration(hours: 47));

    expect(
      await checks((id) async {
        asked.add(id);
        return true;
      }).run(),
      isEmpty,
    );
    expect(asked, isEmpty);
  });

  test(
    'after 48 hours a route still on Strava stays, its check moves on',
    () async {
      final id = await imported('1');
      final asked = <String>[];
      now = now.add(const Duration(hours: 49));

      expect(
        await checks((routeId) async {
          asked.add(routeId);
          return true;
        }).run(),
        isEmpty,
      );
      expect(asked, ['1']);
      expect(await fetchedAt(id), now);

      // Checked just now: not asked again for another 48 hours.
      asked.clear();
      now = now.add(const Duration(hours: 24));
      await checks((routeId) async {
        asked.add(routeId);
        return true;
      }).run();
      expect(asked, isEmpty);
    },
  );

  test('a route gone on Strava (404) is deleted', () async {
    final gone = await imported('1');
    final kept = await imported('2');
    now = now.add(const Duration(days: 3));

    final removed = await checks((routeId) async => routeId != '1').run();

    expect(removed, [gone]);
    expect(await routes.routeById(gone), isNull);
    expect(await routes.routeById(kept), isNotNull);
  });

  test(
    'a route that cannot be checked stays up to 7 days, then goes',
    () async {
      final id = await imported('1');
      Future<bool> offline(String _) async => throw IntegrationException(
        IntegrationFailure.unreachable,
        (l10n) => l10n.relayUnreachable,
      );

      now = now.add(const Duration(days: 3));
      expect(await checks(offline).run(), isEmpty);
      expect(await routes.routeById(id), isNotNull);

      now = now.add(const Duration(days: 5));
      expect(await checks(offline).run(), [id]);
      expect(await routes.routeById(id), isNull);
    },
  );

  test('with Strava disconnected nothing is asked; after 7 days the route '
      'goes', () async {
    final id = await imported('1');

    now = now.add(const Duration(days: 6));
    expect(await checks(null).run(), isEmpty);
    expect(await routes.routeById(id), isNotNull);

    now = now.add(const Duration(days: 2));
    expect(await checks(null).run(), [id]);
  });

  test('a route edited from a Strava route keeps the edits and is checked '
      'the same way', () async {
    final id = await imported('1');
    final edited = await routes.savePlannedRoute(
      id: id,
      name: 'Edited',
      route: syntheticRoute(),
      waypoints: const <Waypoint>[
        Waypoint(pos: LatLng(48, 11), kind: WaypointKind.start),
        Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
      ],
      options: const RoutingOptions(),
    );
    now = now.add(const Duration(days: 3));

    expect(await checks((_) async => true).run(), isEmpty);

    final after = (await routes.routeById(id))!;
    expect(after.name, 'Edited');
    expect(after.geometryBlob, edited.geometryBlob);
    expect(after.fromStrava, isTrue);
    expect(after.updatedAt, edited.updatedAt);
    expect(await fetchedAt(id), now);

    now = now.add(const Duration(days: 3));
    expect(await checks((_) async => false).run(), [id]);
  });

  test('routes from elsewhere are never touched', () async {
    final own = await routes.saveImportedRoute(
      name: 'Mine',
      points: _track,
      source: RouteSource.importedGpx,
    );
    now = now.add(const Duration(days: 30));
    final asked = <String>[];

    expect(
      await checks((id) async {
        asked.add(id);
        return false;
      }).run(),
      isEmpty,
    );
    expect(asked, isEmpty);
    expect(await routes.routeById(own.id), isNotNull);
  });

  test('Strava\'s quota stops the run: nothing more is asked', () async {
    await imported('1');
    await imported('2');
    now = now.add(const Duration(days: 3));
    final asked = <String>[];

    await checks((routeId) async {
      asked.add(routeId);
      throw IntegrationException(
        IntegrationFailure.rateLimited,
        (l10n) => l10n.relayTooManyRequests,
      );
    }).run();

    expect(asked, hasLength(1));
  });

  test('at most 30 routes are asked about in one run', () async {
    for (var i = 0; i < 35; i++) {
      await imported('$i');
    }
    now = now.add(const Duration(days: 3));
    var asked = 0;

    await checks((_) async {
      asked++;
      return true;
    }).run();

    expect(asked, StravaRouteChecks.maxChecksPerRun);
  });

  group('StravaClient.routeExists', () {
    StravaClient client(FakeResponse answer) => StravaClient(
      dio: dioWith(
        FakeApiAdapter((_) => answer),
        baseUrl: '$testProxyBase/strava',
      ),
    );

    test('a route is there', () async {
      expect(
        await client(FakeResponse.json(<String, Object?>{'id': 1}))
            .routeExists('1'),
        isTrue,
      );
    });

    test("Strava's 404 is a route that is gone", () async {
      expect(
        await client(
          FakeResponse.json(<String, Object?>{
            'message': 'Record Not Found',
          }, status: 404),
        ).routeExists('1'),
        isFalse,
      );
    });

    test("the relay's own 404 is not an answer about the route", () async {
      await expectLater(
        client(
          FakeResponse.json(<String, Object?>{
            'error': <String, Object?>{'code': 'not_found', 'message': 'x'},
          }, status: 404),
        ).routeExists('1'),
        throwsA(isA<IntegrationException>()),
      );
    });

    test('any other failure throws', () async {
      await expectLater(
        client(FakeResponse.json(<String, Object?>{}, status: 500))
            .routeExists('1'),
        throwsA(isA<IntegrationException>()),
      );
    });
  });
}
