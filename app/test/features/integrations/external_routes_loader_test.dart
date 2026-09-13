import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/application/external_routes_loader.dart';
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/data/external_route_cache.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_providers.dart';
import 'package:velorki/features/integrations/strava/data/strava_providers.dart';

import 'support/fake_dio.dart';
import 'support/fakes.dart';
import 'support/pump.dart';

const Map<String, Object?> _stravaRoute = <String, Object?>{
  'id_str': '4242',
  'name': 'Sunday loop',
  'distance': 42500.0,
  'elevation_gain': 620.0,
  'description': 'The good one',
  'created_at': '2026-05-01T08:00:00Z',
};

const Map<String, Object?> _rwgpsRoute = <String, Object?>{
  'id': 99,
  'name': 'Isar tour',
  'distance': 31000.0,
  'elevation_gain': 210.0,
};

ConnectedAccount _account(IntegrationService service, {String? athleteId}) =>
    ConnectedAccount(
      service: service,
      accessToken: 'token',
      expiresAt: DateTime.now().add(const Duration(hours: 6)),
      athleteId: athleteId,
    );

/// A container with both services connected, so either source can be built.
Future<ProviderContainer> _connectedContainer({
  Map<IntegrationService, ConnectedAccount>? accounts,
  Map<String, Object> initialPrefs = const <String, Object>{},
}) async {
  final container = await integrationsContainer(
    relay: FakeRelayClient(),
    initialPrefs: initialPrefs,
    accounts:
        accounts ??
        <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _account(
            IntegrationService.strava,
            athleteId: '42',
          ),
          IntegrationService.rwgps: _account(IntegrationService.rwgps),
        },
  );
  await container.read(connectedAccountsProvider.future);
  return container;
}

/// Answers both services' requests from one handler.
FakeApiAdapter _intercept(
  ProviderContainer container,
  FakeResponse Function(RequestOptions options) handler,
) {
  final adapter = FakeApiAdapter(handler);
  container.read(stravaDioProvider).httpClientAdapter = adapter;
  container.read(rwgpsDioProvider).httpClientAdapter = adapter;
  return adapter;
}

void main() {
  group('which source a service has', () {
    test('nothing is connected, so there is no source at all', () async {
      final container = await _connectedContainer(
        accounts: const <IntegrationService, ConnectedAccount>{},
      );

      for (final service in IntegrationService.values) {
        expect(container.read(externalRoutesSourceProvider(service)), isNull);
        expect(container.read(externalRoutesLoaderProvider(service)), isNull);
      }
    });

    test('a connected Strava athlete gets a Strava source', () async {
      final container = await _connectedContainer();

      final source = container.read(
        externalRoutesSourceProvider(IntegrationService.strava),
      );

      expect(source, isA<StravaRoutesSource>());
      expect(source!.service, IntegrationService.strava);
      expect((source as StravaRoutesSource).athleteId, '42');
    });

    test('Strava without an athlete id has no source to read', () async {
      // Strava has no "current athlete" route list, so an account that never
      // learnt its athlete id cannot be listed.
      final container = await _connectedContainer(
        accounts: <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _account(IntegrationService.strava),
        },
      );

      expect(
        container.read(externalRoutesSourceProvider(IntegrationService.strava)),
        isNull,
      );
    });

    test('a connected Ride with GPS account gets its source', () async {
      final container = await _connectedContainer();

      final source = container.read(
        externalRoutesSourceProvider(IntegrationService.rwgps),
      );

      expect(source, isA<RwgpsRoutesSource>());
      expect(source!.service, IntegrationService.rwgps);
    });

    test('the loader goes away when the account is disconnected', () async {
      final container = await _connectedContainer();
      container.listen(
        externalRoutesLoaderProvider(IntegrationService.rwgps),
        (_, _) {},
      );
      expect(
        container.read(externalRoutesLoaderProvider(IntegrationService.rwgps)),
        isNotNull,
      );

      await container
          .read(connectedAccountsProvider.notifier)
          .remove(IntegrationService.rwgps);

      expect(
        container.read(externalRoutesLoaderProvider(IntegrationService.rwgps)),
        isNull,
      );
    });
  });

  group('reading the list through the real clients', () {
    test('a Strava route becomes the shared summary', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<Object?>[_stravaRoute]),
      );

      final result = await container
          .read(externalRoutesLoaderProvider(IntegrationService.strava))!
          .load();

      expect(result.fromCache, isFalse);
      final route = result.routes.single;
      expect(route.id, '4242');
      expect(route.name, 'Sunday loop');
      expect(route.distanceM, 42500);
      expect(route.elevationGainM, 620);
      expect(route.description, 'The good one');
      expect(route.createdAt, DateTime.utc(2026, 5, 1, 8));
      expect(adapter.requests.single.path, contains('/athletes/42/routes'));
    });

    test('a Ride with GPS route becomes the same shape', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{
          'routes': <Object?>[_rwgpsRoute],
        }),
      );

      final result = await container
          .read(externalRoutesLoaderProvider(IntegrationService.rwgps))!
          .load();

      final route = result.routes.single;
      expect(route.id, '99');
      expect(route.name, 'Isar tour');
      expect(route.distanceM, 31000);
      expect(route.elevationGainM, 210);
      expect(adapter.requests.single.path, contains('/routes.json'));
    });

    test('the GPX of one route is fetched on demand', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.text('<gpx></gpx>'),
      );

      final bytes = await container
          .read(externalRoutesLoaderProvider(IntegrationService.strava))!
          .gpx('4242');

      expect(utf8.decode(bytes), '<gpx></gpx>');
      expect(adapter.requests.single.path, contains('/routes/4242/export_gpx'));
    });

    test('a Ride with GPS route exports its own GPX', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.text('<gpx>rwgps</gpx>'),
      );

      final bytes = await container
          .read(externalRoutesLoaderProvider(IntegrationService.rwgps))!
          .gpx('99');

      expect(utf8.decode(bytes), '<gpx>rwgps</gpx>');
      expect(adapter.requests.single.path, contains('/routes/99.gpx'));
    });
  });

  group('the seven-day cache the loaders share', () {
    test('a second read is served without touching the network', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<Object?>[_stravaRoute]),
      );
      final loader = container.read(
        externalRoutesLoaderProvider(IntegrationService.strava),
      )!;

      await loader.load();
      final second = await loader.load();

      expect(second.fromCache, isTrue);
      expect(second.routes.single.name, 'Sunday loop');
      expect(adapter.requests, hasLength(1));
    });

    test('forceRefresh goes back to the service', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<Object?>[_stravaRoute]),
      );
      final loader = container.read(
        externalRoutesLoaderProvider(IntegrationService.strava),
      )!;

      await loader.load();
      final refreshed = await loader.load(forceRefresh: true);

      expect(refreshed.fromCache, isFalse);
      expect(adapter.requests, hasLength(2));
    });

    test('a list read more than seven days ago is fetched again', () async {
      final stale = DateTime.now().toUtc().subtract(const Duration(days: 8));
      final key = ExternalRouteListCache.keyFor(IntegrationService.strava);
      final container = await _connectedContainer(
        initialPrefs: <String, Object>{
          key: jsonEncode(<String, Object?>{
            'fetched_at': stale.toIso8601String(),
            'routes': <Object?>[
              <String, Object?>{'id': '1', 'name': 'Last summer'},
            ],
          }),
        },
      );
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<Object?>[_stravaRoute]),
      );

      final result = await container
          .read(externalRoutesLoaderProvider(IntegrationService.strava))!
          .load();

      expect(result.fromCache, isFalse);
      expect(result.routes.single.name, 'Sunday loop');
      expect(adapter.requests, hasLength(1));
    });

    test('a list read six days ago is still good', () async {
      final fresh = DateTime.now().toUtc().subtract(const Duration(days: 6));
      final key = ExternalRouteListCache.keyFor(IntegrationService.strava);
      final container = await _connectedContainer(
        initialPrefs: <String, Object>{
          key: jsonEncode(<String, Object?>{
            'fetched_at': fresh.toIso8601String(),
            'routes': <Object?>[
              <String, Object?>{'id': '1', 'name': 'Last week'},
            ],
          }),
        },
      );
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<Object?>[_stravaRoute]),
      );

      final result = await container
          .read(externalRoutesLoaderProvider(IntegrationService.strava))!
          .load();

      expect(result.fromCache, isTrue);
      expect(result.routes.single.name, 'Last week');
      expect(result.fetchedAt, fresh);
      expect(adapter.requests, isEmpty);
    });

    test('the two services do not share each other\'s list', () async {
      final container = await _connectedContainer();
      _intercept(container, (options) {
        if (options.path.contains('ridewithgps')) {
          return FakeResponse.json(<String, Object?>{
            'routes': <Object?>[_rwgpsRoute],
          });
        }
        return FakeResponse.json(<Object?>[_stravaRoute]);
      });

      await container
          .read(externalRoutesLoaderProvider(IntegrationService.strava))!
          .load();

      final cache = container.read(externalRouteListCacheProvider);
      expect(cache.read(IntegrationService.strava), isNotNull);
      expect(cache.read(IntegrationService.rwgps), isNull);
    });

    test('a disconnect can clear one service\'s list', () async {
      final container = await _connectedContainer();
      _intercept(
        container,
        (options) => FakeResponse.json(<Object?>[_stravaRoute]),
      );
      final cache = container.read(externalRouteListCacheProvider);
      await container
          .read(externalRoutesLoaderProvider(IntegrationService.strava))!
          .load();

      await cache.clear(IntegrationService.strava);

      expect(cache.read(IntegrationService.strava), isNull);
    });
  });

  group('when the service says no', () {
    test('a server error is the loader\'s own exception, not a raw '
        'DioException', () async {
      final container = await _connectedContainer();
      _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{
          'message': 'Server Error',
        }, status: 500),
      );

      final e = await integrationFailure(
        () => container
            .read(externalRoutesLoaderProvider(IntegrationService.strava))!
            .load(),
      );

      expect(e.failure, IntegrationFailure.serviceError);
      // Nothing was cached, so the next attempt goes back to the service.
      expect(
        container
            .read(externalRouteListCacheProvider)
            .read(IntegrationService.strava),
        isNull,
      );
    });

    test('a rejected token is reported as not connected', () async {
      final container = await _connectedContainer();
      _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{}, status: 401),
      );

      final e = await integrationFailure(
        () => container
            .read(externalRoutesLoaderProvider(IntegrationService.rwgps))!
            .load(),
      );

      expect(e.failure, IntegrationFailure.notConnected);
    });

    test('a failed refresh leaves the cached list alone', () async {
      final container = await _connectedContainer();
      var calls = 0;
      _intercept(container, (options) {
        calls++;
        return calls == 1
            ? FakeResponse.json(<Object?>[_stravaRoute])
            : FakeResponse.json(<String, Object?>{}, status: 500);
      });
      final loader = container.read(
        externalRoutesLoaderProvider(IntegrationService.strava),
      )!;
      await loader.load();

      await expectLater(
        loader.load(forceRefresh: true),
        throwsA(isA<IntegrationException>()),
      );

      // The rider keeps the list they had; only a successful fetch replaces it.
      final again = await loader.load();
      expect(again.fromCache, isTrue);
      expect(again.routes.single.name, 'Sunday loop');
    });

    test(
      'an empty GPX export is a service error, not an empty route',
      () async {
        final container = await _connectedContainer();
        _intercept(container, (options) => FakeResponse.text(''));

        final e = await integrationFailure(
          () => container
              .read(externalRoutesLoaderProvider(IntegrationService.strava))!
              .gpx('4242'),
        );

        expect(e.failure, IntegrationFailure.serviceError);
      },
    );
  });

  group('opening a route screen without a connection', () {
    test('names the service that is not connected', () {
      expect(
        notConnectedException(IntegrationService.strava).message,
        'No strava account is connected.',
      );
      expect(
        notConnectedException(IntegrationService.rwgps).failure,
        IntegrationFailure.notConnected,
      );
    });
  });
}
