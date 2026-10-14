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
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/presentation/share_rows.dart';
import 'package:velorki/features/integrations/presentation/strava_brand.dart';
import 'package:velorki/features/sharing/presentation/share_card.dart';
import 'package:velorki_api/velorki_api.dart' show ShareKind;
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

    testWidgets('each Strava route links back to it on Strava, and the '
        'list credits Strava', (tester) async {
      final harness = await pumpList(
        tester,
        source: _FakeSource(IntegrationService.strava, const <ExternalRoute>[
          _sunday,
        ]),
      );

      expect(find.byType(PoweredByStrava), findsOneWidget);
      await tester.tap(find.text(l10n.rideDetailViewOnStrava));
      await tester.pumpAndSettle();
      expect(harness.openedLinks, [
        Uri.parse('https://www.strava.com/routes/4242'),
      ]);
    });

    testWidgets('a Ride with GPS list has no Strava link', (tester) async {
      await pumpList(
        tester,
        source: _FakeSource(IntegrationService.rwgps, const <ExternalRoute>[
          _sunday,
        ]),
      );

      expect(find.text(l10n.rideDetailViewOnStrava), findsNothing);
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

  group('route share card', () {
    SavedRoute route({
      RouteSource source = RouteSource.planned,
      Map<String, String> externalIds = const <String, String>{},
    }) => SavedRoute(
      id: 'r1',
      name: 'Isar loop',
      source: source,
      externalIds: externalIds,
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

    /// A Share button that opens the card for [saved], as the route detail
    /// does.
    Widget opener(SavedRoute saved, {Future<void> Function()? onExportGpx}) =>
        Builder(
          builder: (context) => ShareButton(
            onPressed: () => showShareCard(
              context,
              title: l10n.shareRouteTitle,
              rows: [
                RwgpsRouteShareRow(route: saved),
                StravaRouteShareRow(onExportGpx: onExportGpx ?? () async {}),
                ShareLinkRow(
                  name: saved.name,
                  points: saved.geometry,
                  kind: ShareKind.route,
                  distanceM: saved.distanceM,
                  fromStrava: saved.fromStrava,
                ),
              ],
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text(l10n.shareLinkAction));
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareRouteTitle), findsOneWidget);
    }

    testWidgets('one card: Ride with GPS to connect, Strava explained, the '
        'link', (tester) async {
      var exported = 0;
      await pumpIntegrations(
        tester,
        opener(route(), onExportGpx: () async => exported++),
      );
      await open(tester);

      expect(find.text(l10n.serviceRwgps), findsOneWidget);
      expect(find.text(l10n.shareNotConnected), findsOneWidget);
      expect(find.text(l10n.shareConnect), findsOneWidget);
      expect(find.text(l10n.shareLinkRowTitle), findsOneWidget);
      expect(find.text(l10n.shareLinkTitle), findsOneWidget);

      // Strava's API cannot create routes: the row says so, and a tap
      // explains and offers the GPX export.
      await tester.tap(find.text(l10n.shareStravaRouteBody));
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

    testWidgets('with Ride with GPS connected the row sends the route and '
        'offers to open it', (tester) async {
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
        opener(route()),
        // Free now: no Plus needed to send.
        harness: IntegrationsHarness(
          entitled: false,
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
      await open(tester);

      expect(find.text(l10n.shareRwgpsRouteBody), findsOneWidget);
      await tester.tap(find.text(l10n.shareSend));
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

    testWidgets('without Plus the link row shows the lock', (tester) async {
      await pumpIntegrations(
        tester,
        opener(route()),
        harness: IntegrationsHarness(entitled: false),
      );
      await open(tester);

      expect(find.text(l10n.sharePlusLabel), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text(l10n.shareLinkTitle), findsNothing);
    });

    for (final (label, saved) in [
      ('read from Strava', route(source: RouteSource.strava)),
      (
        'edited from a Strava route',
        route(externalIds: const {'strava_route_id': '77'}),
      ),
    ]) {
      testWidgets('a route $label goes to no other service and into no link', (
        tester,
      ) async {
        final adapter = FakeApiAdapter((_) => FakeResponse.json(const {}));
        await pumpIntegrations(
          tester,
          opener(saved),
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
        await open(tester);

        expect(find.text(l10n.shareNotForStravaRoutes), findsNWidgets(2));
        expect(find.text(l10n.shareSend), findsNothing);
        expect(find.text(l10n.shareLinkTitle), findsNothing);
        expect(adapter.requests, isEmpty);
      });
    }

    test('the sender refuses a Strava route without asking Ride with GPS', () {
      final adapter = FakeApiAdapter((_) => FakeResponse.json(const {}));
      final sender = RouteSender(
        rwgps: RwgpsClient(dio: dioWith(adapter), sleep: _noSleep),
      );
      expect(
        () => sender.sendToRwgps(route(source: RouteSource.strava)),
        throwsA(
          isA<IntegrationException>().having(
            (e) => e.failure,
            'failure',
            IntegrationFailure.rejected,
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    });
  });
}
