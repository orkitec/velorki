import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/integrations/application/connections_controller.dart';
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/data/external_route_cache.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/strava/data/strava_providers.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/pump.dart';

final ConnectedAccount _strava = ConnectedAccount(
  service: IntegrationService.strava,
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresAt: DateTime.utc(2020),
  athleteId: '42',
  scopes: const <String>['read', 'activity:write'],
);

const ConnectedAccount _rwgps = ConnectedAccount(
  service: IntegrationService.rwgps,
  accessToken: 'rw',
);

final List<TrackPoint> _track = <TrackPoint>[
  for (var i = 0; i < 5; i++)
    TrackPoint(
      LatLng(48 + i * 0.001, 11),
      ele: 500,
      time: DateTime.utc(2026, 9, 12, 10, 0, i * 10),
    ),
];

RideUpload _done(String id) => RideUpload(
  status: RideUploadStatus.done,
  uploadedAt: DateTime.utc(2026, 9, 12, 11),
  activityId: id,
  url: 'https://example.test/$id',
);

/// The library with one route and one ride of each kind, and both route
/// lists cached.
class _Library {
  _Library(this.container, this.db);

  final ProviderContainer container;
  final VelorkiDatabase db;
  late final String stravaRoute;
  late final String ownRoute;
  late final String rwgpsRoute;

  RouteRepository get routes => RouteRepository(db.routesDao);
  RideRepository get rides => RideRepository(db.ridesDao);

  Future<void> seed() async {
    final strava = await routes.saveImportedRoute(
      name: 'From Strava',
      points: _track,
      source: RouteSource.strava,
    );
    await routes.markExternal(
      strava.id,
      externalIds: const <String, Object?>{'strava_route_id': '4242'},
    );
    stravaRoute = strava.id;
    ownRoute = (await routes.saveImportedRoute(
      name: 'Mine',
      points: _track,
      source: RouteSource.importedGpx,
    )).id;
    rwgpsRoute = (await routes.saveImportedRoute(
      name: 'From Ride with GPS',
      points: _track,
      source: RouteSource.rwgps,
    )).id;
    await rides.finalizeRide(
      rideId: 'ride-1',
      name: 'Morning loop',
      points: _track,
      startedAt: DateTime.utc(2026, 9, 12, 10),
      endedAt: DateTime.utc(2026, 9, 12, 10, 1),
    );
    await rides.recordUpload(
      'ride-1',
      serviceId: 'strava',
      upload: _done('5555'),
    );
    await rides.recordUpload('ride-1', serviceId: 'rwgps', upload: _done('9'));
    final cache = container.read(externalRouteListCacheProvider);
    for (final service in IntegrationService.values) {
      await cache.write(service, <Map<String, Object?>>[
        <String, Object?>{'id': '1', 'name': 'Listed'},
      ]);
    }
  }

  /// Everything Strava is gone; everything else is still there.
  Future<void> expectStravaGone() async {
    expect(await routes.routeById(stravaRoute), isNull);
    expect(await routes.routeById(ownRoute), isNotNull);
    expect(await routes.routeById(rwgpsRoute), isNotNull);
    final ride = (await rides.rideById('ride-1'))!;
    expect(ride.uploadFor('strava'), isNull);
    expect(ride.uploadFor('rwgps'), isNotNull);
    final cache = container.read(externalRouteListCacheProvider);
    expect(cache.read(IntegrationService.strava), isNull);
    expect(
      await container
          .read(connectedAccountsRepositoryProvider)
          .read(IntegrationService.strava),
      isNull,
    );
  }
}

void main() {
  late VelorkiDatabase db;

  setUp(() => db = VelorkiDatabase.memory());
  tearDown(() => db.close());

  test('disconnecting Strava revokes, deletes the token and every piece of '
      'Strava data on the phone, and nothing else', () async {
    final connector = FakeConnector(IntegrationService.strava);
    final container = await integrationsContainer(
      accounts: <IntegrationService, ConnectedAccount>{
        IntegrationService.strava: _strava,
        IntegrationService.rwgps: _rwgps,
      },
      extraOverrides: [
        velorkiDatabaseProvider.overrideWithValue(db),
        integrationConnectorProvider.overrideWith(
          (ref, service) =>
              service == IntegrationService.strava ? connector : null,
        ),
      ],
    );
    final library = _Library(container, db);
    await library.seed();
    await container.read(connectedAccountsProvider.future);

    await container
        .read(integrationConnectionsProvider.notifier)
        .disconnect(IntegrationService.strava);

    expect(connector.revokes, 1);
    await library.expectStravaGone();
    // Ride with GPS is untouched.
    expect(
      container.read(connectedAccountProvider(IntegrationService.rwgps)),
      isNotNull,
    );
    expect(
      container
          .read(externalRouteListCacheProvider)
          .read(IntegrationService.rwgps),
      isNotNull,
    );
    // A disconnect confirms by itself; the revoked notice is not for it.
    expect(container.read(stravaAccessLostNoticeProvider), isFalse);
  });

  test('a refresh Strava refuses as revoked deletes the Strava data and '
      'asks for the notice', () async {
    final relay = FakeRelayClient(
      failure: const RelayException(
        RelayError(
          code: RelayErrorCode.authorizationRevoked,
          message: 'Strava no longer accepts this authorization.',
        ),
        statusCode: 400,
      ),
    );
    final container = await integrationsContainer(
      accounts: <IntegrationService, ConnectedAccount>{
        IntegrationService.strava: _strava,
      },
      relay: relay,
      extraOverrides: [velorkiDatabaseProvider.overrideWithValue(db)],
    );
    final library = _Library(container, db);
    await library.seed();
    listenForStravaRevocation(container);

    await expectLater(
      container.read(stravaTokenSourceProvider).account(),
      throwsA(
        isA<IntegrationException>().having(
          (e) => e.failure,
          'failure',
          IntegrationFailure.revoked,
        ),
      ),
    );
    // The deletion runs beside the failed call.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    await library.expectStravaGone();
    expect(container.read(stravaAccessLostNoticeProvider), isTrue);
  });

  test('another refresh failure keeps the connection and the data', () async {
    final relay = FakeRelayClient(
      failure: const RelayException(
        RelayError(
          code: RelayErrorCode.upstreamError,
          message: 'Could not reach the provider.',
        ),
        statusCode: 502,
      ),
    );
    final container = await integrationsContainer(
      accounts: <IntegrationService, ConnectedAccount>{
        IntegrationService.strava: _strava,
      },
      relay: relay,
      extraOverrides: [velorkiDatabaseProvider.overrideWithValue(db)],
    );
    final library = _Library(container, db);
    await library.seed();
    listenForStravaRevocation(container);

    await expectLater(
      container.read(stravaTokenSourceProvider).account(),
      throwsA(isA<IntegrationException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(await library.routes.routeById(library.stravaRoute), isNotNull);
    expect(container.read(stravaAccessLostNoticeProvider), isFalse);
  });

  test('the relay\'s authorization_revoked is the revoked failure', () {
    final e = integrationExceptionFor(
      const RelayException(
        RelayError(
          code: RelayErrorCode.authorizationRevoked,
          message: 'revoked',
        ),
        statusCode: 400,
      ),
    );
    expect(e.failure, IntegrationFailure.revoked);
  });
}
