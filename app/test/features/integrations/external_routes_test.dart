import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/import_export/data/import_repository.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';
import 'package:velorki/features/integrations/application/external_route_importer.dart';
import 'package:velorki/features/integrations/application/external_routes_loader.dart';
import 'package:velorki/features/integrations/common/data/external_route_cache.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/external_route.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/planner/data/route_repository.dart';

import '../import_export/support/fixtures.dart';
import 'support/fakes.dart';

/// A source whose answers the test sets, standing in for either service.
class _FakeSource implements ExternalRoutesSource {
  _FakeSource({
    required this.service,
    this.routes = const <ExternalRoute>[],
    Uint8List? gpx,
  }) : gpx = gpx ?? fixtureBytes('strava.gpx');

  @override
  final IntegrationService service;

  List<ExternalRoute> routes;
  Uint8List gpx;
  Object? failure;
  int fetches = 0;
  final List<String> gpxRequests = <String>[];

  @override
  Future<List<ExternalRoute>> fetchRoutes() async {
    fetches++;
    if (failure != null) throw failure!;
    return routes;
  }

  @override
  Future<Uint8List> fetchGpx(String routeId) async {
    gpxRequests.add(routeId);
    return gpx;
  }
}

const ExternalRoute _sunday = ExternalRoute(
  id: '4242',
  name: 'Sunday loop',
  distanceM: 42500,
  elevationGainM: 620,
);

void main() {
  late SharedPreferences prefs;
  var now = DateTime.utc(2026, 9, 12, 12);

  setUp(() async {
    now = DateTime.utc(2026, 9, 12, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  ExternalRouteListCache cache() =>
      ExternalRouteListCache(prefs, clock: () => now);

  group('the seven-day list cache', () {
    test('a second load comes out of the cache', () async {
      final source = _FakeSource(
        service: IntegrationService.strava,
        routes: const <ExternalRoute>[_sunday],
      );
      final loader = ExternalRoutesLoader(
        source: source,
        cache: cache(),
        clock: () => now,
      );

      final first = await loader.load();
      expect(first.fromCache, isFalse);
      expect(first.routes, hasLength(1));

      final second = await loader.load();
      expect(second.fromCache, isTrue);
      expect(second.routes.single, _sunday);
      expect(source.fetches, 1);
    });

    test('forceRefresh goes back to the service', () async {
      final source = _FakeSource(
        service: IntegrationService.strava,
        routes: const <ExternalRoute>[_sunday],
      );
      final loader = ExternalRoutesLoader(
        source: source,
        cache: cache(),
        clock: () => now,
      );

      await loader.load();
      await loader.load(forceRefresh: true);
      expect(source.fetches, 2);
    });

    test('a list older than seven days is dropped and fetched again', () async {
      final source = _FakeSource(
        service: IntegrationService.strava,
        routes: const <ExternalRoute>[_sunday],
      );
      final loader = ExternalRoutesLoader(
        source: source,
        cache: cache(),
        clock: () => now,
      );
      await loader.load();

      // Six days later it is still good; on the eighth day it is gone.
      now = now.add(const Duration(days: 6));
      expect((await loader.load()).fromCache, isTrue);
      expect(source.fetches, 1);

      now = now.add(const Duration(days: 2));
      expect((await loader.load()).fromCache, isFalse);
      expect(source.fetches, 2);
      expect(
        prefs.getString(
          ExternalRouteListCache.keyFor(IntegrationService.strava),
        ),
        isNotNull,
      );
    });

    test('purgeExpired removes a stale list at launch', () async {
      final loader = ExternalRoutesLoader(
        source: _FakeSource(
          service: IntegrationService.rwgps,
          routes: const <ExternalRoute>[_sunday],
        ),
        cache: cache(),
        clock: () => now,
      );
      await loader.load();
      final key = ExternalRouteListCache.keyFor(IntegrationService.rwgps);
      expect(prefs.getString(key), isNotNull);

      now = now.add(const Duration(days: 8));
      await cache().purgeExpired();
      expect(prefs.getString(key), isNull);
    });

    test('the two services are cached separately', () async {
      await ExternalRoutesLoader(
        source: _FakeSource(
          service: IntegrationService.strava,
          routes: const <ExternalRoute>[_sunday],
        ),
        cache: cache(),
      ).load();

      expect(cache().read(IntegrationService.strava), isNotNull);
      expect(cache().read(IntegrationService.rwgps), isNull);
    });

    test('an unreadable cache entry is discarded', () async {
      await prefs.setString(
        ExternalRouteListCache.keyFor(IntegrationService.strava),
        'not json',
      );
      expect(cache().read(IntegrationService.strava), isNull);
    });
  });

  group('importing one route', () {
    late VelorkiDatabase db;
    late ExternalRouteImporter importer;

    setUp(() {
      db = VelorkiDatabase.memory();
      addTearDown(db.close);
      importer = ExternalRouteImporter(
        ImportRepository(
          RouteRepository(db.routesDao, clock: () => now),
          db.ridesDao,
          clock: () => now,
        ),
        clock: () => now,
      );
    });

    test('a Strava route lands in the library with source strava', () async {
      final source = _FakeSource(
        service: IntegrationService.strava,
        routes: const <ExternalRoute>[_sunday],
      );
      final loader = ExternalRoutesLoader(source: source, cache: cache());

      final listed = (await loader.load()).routes.single;
      final saved = await importer.importRoute(
        service: IntegrationService.strava,
        gpx: await loader.gpx(listed.id),
        externalId: listed.id,
        name: listed.name,
      );

      expect(source.gpxRequests, <String>['4242']);
      expect(saved.name, 'Sunday loop');
      expect(saved.source, RouteSource.strava);
      expect(saved.geometry, isNotEmpty);

      // The row remembers where it came from and when, which is what
      // Strava's seven-day rule is measured against.
      final row = await db.routesDao.routeById(saved.id);
      expect(row!.source, RouteSource.strava);
      expect(row.externalIdsJson, contains('strava_route_id'));
      expect(row.externalIdsJson, contains('4242'));
      expect(row.externalFetchedAt, now);
    });

    test('a Ride with GPS route lands with source rwgps', () async {
      final saved = await importer.importRoute(
        service: IntegrationService.rwgps,
        gpx: fixtureBytes('route.gpx'),
        externalId: '99',
        name: 'From RWGPS',
      );

      expect(saved.source, RouteSource.rwgps);
      final row = await db.routesDao.routeById(saved.id);
      expect(row!.externalIdsJson, contains('rwgps_route_id'));
    });

    test(
      'a GPX the service could not export is reported, not thrown raw',
      () async {
        final e = await integrationFailure(
          () => importer.importRoute(
            service: IntegrationService.strava,
            gpx: Uint8List.fromList(<int>[1, 2, 3]),
            externalId: '1',
            name: 'Broken',
          ),
        );
        expect(e.failure, IntegrationFailure.serviceError);
        expect(e.message, contains('strava'));
      },
    );

    test('a plain file import still gets the format-derived source', () async {
      expect(
        ImportRepository.sourceForFormat(ImportFormat.gpx),
        RouteSource.importedGpx,
      );
      expect(
        ImportRepository.sourceForFormat(ImportFormat.fit),
        RouteSource.importedFit,
      );
    });
  });
}
