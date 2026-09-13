import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/http/user_agent.dart';
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/data/token_bucket.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/strava/data/strava_providers.dart';
import 'package:velorki_api/velorki_api.dart' as relay;

import 'support/fake_dio.dart';
import 'support/fakes.dart';
import 'support/pump.dart';

ConnectedAccount _connected({Duration validFor = const Duration(hours: 6)}) =>
    ConnectedAccount(
      service: IntegrationService.strava,
      accessToken: 'stored-access',
      refreshToken: 'stored-refresh',
      expiresAt: DateTime.now().add(validFor),
      athleteId: '42',
      athleteName: 'Steffen',
    );

/// The token set the relay hands back, valid well past the leeway so the
/// retried request does not refresh a second time.
relay.StravaTokens _fresh() => relay.StravaTokens(
  accessToken: 'refreshed-access',
  refreshToken: 'refreshed-refresh',
  expiresAt:
      DateTime.now().add(const Duration(hours: 6)).millisecondsSinceEpoch ~/
      1000,
);

/// A container with a stored Strava account and a relay that will refresh it.
Future<ProviderContainer> _connectedContainer({
  FakeRelayClient? relayClient,
  AppConfig config = configuredBuild,
  Map<IntegrationService, ConnectedAccount>? accounts,
}) async {
  final container = await integrationsContainer(
    config: config,
    relay: relayClient ?? FakeRelayClient(refreshedStravaTokens: _fresh()),
    accounts:
        accounts ??
        <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _connected(),
        },
  );
  // The accounts notifier reads secure storage asynchronously; everything that
  // shows an athlete waits for that first read.
  await container.read(connectedAccountsProvider.future);
  return container;
}

/// Puts [adapter] in front of the dio the providers built, so the requests the
/// real wiring makes can be answered without a network.
FakeApiAdapter _intercept(
  ProviderContainer container,
  FakeResponse Function(RequestOptions options) handler,
) {
  final adapter = FakeApiAdapter(handler);
  container.read(stravaDioProvider).httpClientAdapter = adapter;
  return adapter;
}

void main() {
  group('whether this build has Strava', () {
    test('a relay and a client id are both needed', () async {
      final container = await integrationsContainer();
      expect(container.read(stravaConfiguredProvider), isTrue);
    });

    test('a build without a relay has no Strava', () async {
      final container = await integrationsContainer(
        config: const AppConfig(stravaClientId: '1234'),
      );
      expect(container.read(stravaConfiguredProvider), isFalse);
    });

    test('a build without a client id has no Strava', () async {
      final container = await integrationsContainer(
        config: const AppConfig(apiUrl: 'https://relay.test'),
      );
      expect(container.read(stravaConfiguredProvider), isFalse);
    });

    test('a rider\'s own relay URL switches Strava on', () async {
      final container = await integrationsContainer(
        config: const AppConfig(stravaClientId: '1234'),
      );
      expect(container.read(stravaConfiguredProvider), isFalse);

      await container
          .read(serverOverridesProvider.notifier)
          .setApiUrl('https://my-own-relay.test');

      expect(container.read(stravaConfiguredProvider), isTrue);
    });
  });

  group('the connector', () {
    test('carries the client id and the callback scheme', () async {
      final container = await integrationsContainer(
        config: const AppConfig(
          apiUrl: 'https://relay.test',
          stravaClientId: '1234',
          oauthScheme: 'velorki-dev',
        ),
        relay: FakeRelayClient(),
      );

      final connector = container.read(stravaConnectorProvider)!;

      expect(connector.clientId, '1234');
      expect(connector.callbackScheme, 'velorki-dev');
      expect(connector.flow.callbackScheme, 'velorki-dev');
      expect(connector.service, IntegrationService.strava);
    });

    test('a build without a relay has no connector', () async {
      final container = await integrationsContainer(
        config: const AppConfig(stravaClientId: '1234'),
      );
      expect(container.read(stravaConnectorProvider), isNull);
    });

    test('a build without a client id has no connector', () async {
      final container = await integrationsContainer(
        config: const AppConfig(apiUrl: 'https://relay.test'),
        relay: FakeRelayClient(),
      );
      expect(container.read(stravaConnectorProvider), isNull);
    });

    test('a connector appears once a relay URL is configured', () async {
      final container = await integrationsContainer(
        config: const AppConfig(stravaClientId: '1234'),
      );
      expect(container.read(stravaConnectorProvider), isNull);

      await container
          .read(serverOverridesProvider.notifier)
          .setApiUrl('https://my-own-relay.test');

      expect(container.read(stravaConnectorProvider), isNotNull);
    });

    test('the installed Strava app is only offered on iOS', () async {
      final container = await integrationsContainer(relay: FakeRelayClient());
      expect(container.read(stravaConnectorProvider)!.preferAppToApp, isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ios = await integrationsContainer(relay: FakeRelayClient());
      expect(ios.read(stravaConnectorProvider)!.preferAppToApp, isTrue);
    });

    test('revoking sends the account\'s token to Strava', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{}),
      );

      await container.read(stravaConnectorProvider)!.revoke(_connected());

      expect(adapter.requests.single.path, contains('/oauth/deauthorize'));
      expect(
        adapter.requests.single.queryParameters['access_token'],
        'stored-access',
      );
    });
  });

  group('the dio Strava is talked to over', () {
    test('identifies the app and asks for JSON', () async {
      final container = await _connectedContainer();
      final options = container.read(stravaDioProvider).options;

      expect(options.headers['User-Agent'], velorkiUserAgent);
      expect(options.headers['Accept'], 'application/json');
      expect(options.connectTimeout, const Duration(seconds: 20));
      expect(options.receiveTimeout, const Duration(seconds: 60));
      expect(options.sendTimeout, const Duration(minutes: 2));
    });

    test('puts the stored access token on every request', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(const <Object?>[]),
      );

      await container.read(stravaClientProvider).listRoutes(athleteId: '42');

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer stored-access',
      );
    });

    test('a 401 is refreshed through the relay and retried', () async {
      final relayClient = FakeRelayClient(refreshedStravaTokens: _fresh());
      final container = await _connectedContainer(relayClient: relayClient);
      var calls = 0;
      final adapter = _intercept(container, (options) {
        calls++;
        return calls == 1
            ? FakeResponse.json(<String, Object?>{
                'message': 'Authorization Error',
              }, status: 401)
            : FakeResponse.json(const <Object?>[]);
      });

      await container.read(stravaClientProvider).listRoutes(athleteId: '42');

      expect(relayClient.refreshedWith, <String>['stored-refresh']);
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer refreshed-access',
      );
    });

    test('the refreshed account is stored and published', () async {
      final container = await _connectedContainer();
      var calls = 0;
      _intercept(container, (options) {
        calls++;
        return calls == 1
            ? FakeResponse.json(<String, Object?>{}, status: 401)
            : FakeResponse.json(const <Object?>[]);
      });

      await container.read(stravaClientProvider).listRoutes(athleteId: '42');

      // The token source writes the rotated set; its onRefreshed brings the
      // settings tile up to date without a second read of secure storage.
      final stored = await container
          .read(connectedAccountsRepositoryProvider)
          .read(IntegrationService.strava);
      expect(stored!.refreshToken, 'refreshed-refresh');
      expect(
        container
            .read(connectedAccountProvider(IntegrationService.strava))!
            .accessToken,
        'refreshed-access',
      );
      // The athlete the account was connected as is kept.
      expect(stored.athleteId, '42');
    });

    test('a refresh the relay refuses leaves the 401 to the caller', () async {
      final relayClient = FakeRelayClient(
        failure: const relay.RelayException(
          relay.RelayError(
            code: relay.RelayErrorCode.notEntitled,
            message: 'no entitlement',
          ),
        ),
      );
      final container = await _connectedContainer(relayClient: relayClient);
      var calls = 0;
      _intercept(container, (options) {
        calls++;
        return FakeResponse.json(<String, Object?>{}, status: 401);
      });

      final e = await integrationFailure(
        () => container.read(stravaClientProvider).listRoutes(athleteId: '42'),
      );

      // Strava's own 401 wins: the refresh failure is logged, not shown.
      expect(e.failure, IntegrationFailure.notConnected);
      expect(calls, 1);
      // The stored account is deliberately kept — the rider may simply be off
      // Velorki Plus for a moment, and dropping the token would force a
      // reconnect they cannot do until they are back on it.
      final stored = await container
          .read(connectedAccountsRepositoryProvider)
          .read(IntegrationService.strava);
      expect(stored!.accessToken, 'stored-access');
    });

    test('an error that is not a 401 is passed through untouched', () async {
      final relayClient = FakeRelayClient(refreshedStravaTokens: _fresh());
      final container = await _connectedContainer(relayClient: relayClient);
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{
          'message': 'Server Error',
        }, status: 500),
      );

      final e = await integrationFailure(
        () => container.read(stravaClientProvider).listRoutes(athleteId: '42'),
      );

      expect(e.failure, IntegrationFailure.serviceError);
      expect(adapter.requests, hasLength(1));
      expect(relayClient.refreshedWith, isEmpty);
    });

    test('a request without a connected account never flies', () async {
      final container = await integrationsContainer(relay: FakeRelayClient());
      await container.read(connectedAccountsProvider.future);
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(const <Object?>[]),
      );

      final e = await integrationFailure(
        () => container.read(stravaClientProvider).listRoutes(athleteId: '42'),
      );

      expect(e.failure, IntegrationFailure.notConnected);
      expect(adapter.requests, isEmpty);
    });

    test('the client is closed when the container goes away', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(const <Object?>[]),
      );

      container.dispose();

      expect(adapter.closes, 1);
    });
  });

  group('the Strava client', () {
    test('is built on the dio the provider wired', () async {
      final container = await _connectedContainer();
      expect(
        container.read(stravaClientProvider).dio,
        same(container.read(stravaDioProvider)),
      );
    });

    test('shares the app-wide read bucket', () async {
      final container = await _connectedContainer();
      _intercept(container, (options) => FakeResponse.json(const <Object?>[]));

      final bucket = container.read(stravaReadBucketProvider);
      while (bucket.tryConsume()) {}

      final e = await integrationFailure(
        () => container.read(stravaClientProvider).listRoutes(athleteId: '42'),
      );
      expect(e.failure, IntegrationFailure.rateLimited);
    });
  });

  group('the connected athlete', () {
    test('is nobody while nothing is connected', () async {
      final container = await integrationsContainer(relay: FakeRelayClient());
      await container.read(connectedAccountsProvider.future);

      expect(container.read(stravaAthleteIdProvider), isNull);
    });

    test('is the stored athlete id once an account is there', () async {
      final container = await _connectedContainer();

      expect(container.read(stravaAthleteIdProvider), '42');
    });

    test('goes away again when the account is disconnected', () async {
      final container = await _connectedContainer();
      container.listen(stravaAthleteIdProvider, (_, _) {});

      await container
          .read(connectedAccountsProvider.notifier)
          .remove(IntegrationService.strava);

      expect(container.read(stravaAthleteIdProvider), isNull);
    });
  });
}
