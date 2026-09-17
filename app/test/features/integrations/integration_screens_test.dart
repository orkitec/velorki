import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/import_export/data/import_repository.dart';
import 'package:velorki/features/integrations/application/external_route_importer.dart';
import 'package:velorki/features/integrations/application/external_routes_loader.dart';
import 'package:velorki/features/integrations/application/route_sender.dart';
import 'package:velorki/features/integrations/common/data/external_route_cache.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/external_route.dart';
import 'package:velorki/features/integrations/presentation/external_routes_screen.dart';
import 'package:velorki/features/integrations/presentation/route_send_menu.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_client.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
import '../import_export/support/fixtures.dart';
import 'support/fake_dio.dart';
import 'support/pump.dart';

Future<void> _noSleep(Duration _) async {}

const ConnectedAccount _stravaAccount = ConnectedAccount(
  service: IntegrationService.strava,
  accessToken: 'access',
  athleteId: '42',
);

const ConnectedAccount _rwgpsAccount = ConnectedAccount(
  service: IntegrationService.rwgps,
  accessToken: 'rw',
  athleteId: '1',
);

/// A source with canned routes and one GPX.
class _FakeSource implements ExternalRoutesSource {
  _FakeSource(this.service, this.routes, {Uint8List? gpx})
    : gpx = gpx ?? fixtureBytes('strava.gpx');

  @override
  final IntegrationService service;

  final List<ExternalRoute> routes;
  final Uint8List gpx;
  int fetches = 0;

  @override
  Future<List<ExternalRoute>> fetchRoutes() async {
    fetches++;
    return routes;
  }

  @override
  Future<Uint8List> fetchGpx(String routeId) async => gpx;
}

const ExternalRoute _sunday = ExternalRoute(
  id: '4242',
  name: 'Sunday loop',
  distanceM: 42500,
  elevationGainM: 620,
);

void main() {
  group('ExternalRoutesScreen', () {
    late VelorkiDatabase db;

    setUp(() {
      db = VelorkiDatabase.memory();
      addTearDown(db.close);
    });

    Future<IntegrationsHarness> pumpList(
      WidgetTester tester, {
      required _FakeSource source,
      bool connected = true,
    }) => pumpIntegrations(
      tester,
      ExternalRoutesScreen(service: source.service),
      harness: IntegrationsHarness(
        accounts: connected
            ? <IntegrationService, ConnectedAccount>{
                source.service: source.service == IntegrationService.strava
                    ? _stravaAccount
                    : _rwgpsAccount,
              }
            : null,
      ),
      extraOverrides: [
        externalRoutesLoaderProvider.overrideWith(
          (ref, service) => connected && service == source.service
              ? ExternalRoutesLoader(
                  source: source,
                  cache: ref.watch(externalRouteListCacheProvider),
                )
              : null,
        ),
        externalRouteImporterProvider.overrideWithValue(
          ExternalRouteImporter(
            ImportRepository(RouteRepository(db.routesDao), db.ridesDao),
          ),
        ),
      ],
    );

    testWidgets('lists the routes with distance, ascent and date', (
      tester,
    ) async {
      await pumpList(
        tester,
        source: _FakeSource(IntegrationService.strava, const <ExternalRoute>[
          _sunday,
        ]),
      );

      expect(find.text(l10n.externalRoutesTitle('Strava')), findsOneWidget);
      expect(find.text('Sunday loop'), findsOneWidget);
      expect(find.textContaining(testDistance(42500)), findsOneWidget);
      expect(find.textContaining('620 m'), findsOneWidget);
      expect(find.text(l10n.externalRoutesImport), findsOneWidget);
    });

    testWidgets('Import writes a route with source strava', (tester) async {
      await pumpList(
        tester,
        source: _FakeSource(IntegrationService.strava, const <ExternalRoute>[
          _sunday,
        ]),
      );

      await tester.tap(find.text(l10n.externalRoutesImport));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.externalRoutesImported('Sunday loop')),
        findsOneWidget,
      );
      final rows = await db.routesDao.allRoutes();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Sunday loop');
      expect(rows.single.source, RouteSource.strava);
      expect(rows.single.externalFetchedAt, isNotNull);
    });

    testWidgets('an empty account says so', (tester) async {
      await pumpList(
        tester,
        source: _FakeSource(IntegrationService.rwgps, const <ExternalRoute>[]),
      );

      expect(
        find.textContaining(l10n.externalRoutesEmpty('Ride with GPS')),
        findsOneWidget,
      );
    });

    testWidgets('without a connection it points at Settings', (tester) async {
      await pumpList(
        tester,
        source: _FakeSource(IntegrationService.strava, const <ExternalRoute>[
          _sunday,
        ]),
        connected: false,
      );

      expect(
        find.textContaining(l10n.externalRoutesNotConnected('Strava')),
        findsOneWidget,
      );
    });

    testWidgets('Refresh goes back to the service', (tester) async {
      final source = _FakeSource(
        IntegrationService.strava,
        const <ExternalRoute>[_sunday],
      );
      await pumpList(tester, source: source);
      expect(source.fetches, 1);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(source.fetches, 2);
    });
  });

  group('RouteSendMenu', () {
    SavedRoute route() => SavedRoute(
      id: 'r1',
      name: 'Isar loop',
      source: RouteSource.planned,
      profile: RouteProfile.trekking,
      createdAt: DateTime.utc(2026, 9, 12),
      updatedAt: DateTime.utc(2026, 9, 12),
      distanceM: 10000,
      ascentM: 100,
      descentM: 100,
      bounds: const BoundingBox(south: 48, west: 11, north: 48.1, east: 11.1),
      geometryBlob: PackedTrack.encode(const <TrackPoint>[
        TrackPoint(LatLng(48, 11), ele: 500),
        TrackPoint(LatLng(48.01, 11.01), ele: 510),
      ]),
      waypoints: const <Waypoint>[
        Waypoint(pos: LatLng(48, 11), kind: WaypointKind.start),
        Waypoint(pos: LatLng(48.01, 11.01), kind: WaypointKind.end),
      ],
      options: const RoutingOptions(),
    );

    testWidgets('Strava explains that its API cannot create routes', (
      tester,
    ) async {
      var exported = 0;
      await pumpIntegrations(
        tester,
        RouteSendMenu(route: route(), onExportGpx: () async => exported++),
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.routeDetailSendToStrava), findsOneWidget);
      // Nothing is connected, so Ride with GPS is not offered.
      expect(find.text(l10n.routeDetailSendToRwgps), findsNothing);

      await tester.tap(find.text(l10n.routeDetailSendToStrava));
      await tester.pumpAndSettle();

      expect(find.text(l10n.routeDetailSendToStravaTitle), findsOneWidget);
      expect(
        find.textContaining(l10n.routeDetailSendToStravaBody),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n.routeDetailSendToStravaAction));
      await tester.pumpAndSettle();
      expect(exported, 1);
    });

    testWidgets('Ride with GPS uploads the route and offers to open it', (
      tester,
    ) async {
      final adapter = FakeApiAdapter(
        (_) => FakeResponse.json(<String, Object?>{
          'task': <String, Object?>{
            'id': 9,
            'status': 'completed',
            'items': <Object?>[
              <String, Object?>{'item_type': 'route', 'item_id': 4242},
            ],
            'errors': <Object?>[],
          },
        }, status: 202),
      );
      final harness = await pumpIntegrations(
        tester,
        RouteSendMenu(route: route(), onExportGpx: () async {}),
        harness: IntegrationsHarness(
          accounts: const <IntegrationService, ConnectedAccount>{
            IntegrationService.rwgps: _rwgpsAccount,
          },
        ),
        extraOverrides: [
          routeSenderProvider.overrideWithValue(
            RouteSender(
              rwgps: RwgpsClient(dio: dioWith(adapter), sleep: _noSleep),
            ),
          ),
        ],
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.routeDetailSendToRwgps));
      await tester.pumpAndSettle();

      expect(find.text(l10n.routeDetailSent('Ride with GPS')), findsOneWidget);
      expect(multipartFields(adapter.requests.single)['name'], 'Isar loop');

      await tester.tap(find.text(l10n.routeDetailOpenSent));
      await tester.pumpAndSettle();
      expect(
        harness.openedLinks.single.toString(),
        'https://ridewithgps.com/routes/4242',
      );
    });
  });
}
