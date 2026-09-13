import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/http/user_agent.dart';
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_providers.dart';

import 'support/fake_dio.dart';
import 'support/fakes.dart';
import 'support/pump.dart';

ConnectedAccount _connected({DateTime? expiresAt, String? refreshToken}) =>
    ConnectedAccount(
      service: IntegrationService.rwgps,
      accessToken: 'stored-access',
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      athleteId: '7',
      athleteName: 'Steffen',
    );

/// A container with a connected Ride with GPS account.
Future<ProviderContainer> _connectedContainer({
  ConnectedAccount? account,
  AppConfig config = configuredBuild,
  List<Override> extraOverrides = const <Override>[],
}) async {
  final container = await integrationsContainer(
    config: config,
    relay: FakeRelayClient(),
    accounts: <IntegrationService, ConnectedAccount>{
      IntegrationService.rwgps: account ?? _connected(),
    },
    extraOverrides: extraOverrides,
  );
  await container.read(connectedAccountsProvider.future);
  return container;
}

/// Answers the requests the provider-built dio makes.
FakeApiAdapter _intercept(
  ProviderContainer container,
  FakeResponse Function(RequestOptions options) handler,
) {
  final adapter = FakeApiAdapter(handler);
  container.read(rwgpsDioProvider).httpClientAdapter = adapter;
  return adapter;
}

void main() {
  group('whether this build has Ride with GPS', () {
    test('a relay and a client id are both needed', () async {
      final container = await integrationsContainer();
      expect(container.read(rwgpsConfiguredProvider), isTrue);
    });

    test('a build without a relay has none', () async {
      final container = await integrationsContainer(
        config: const AppConfig(rwgpsClientId: 'abcd'),
      );
      expect(container.read(rwgpsConfiguredProvider), isFalse);
    });

    test('a build without a client id has none', () async {
      final container = await integrationsContainer(
        config: const AppConfig(apiUrl: 'https://relay.test'),
      );
      expect(container.read(rwgpsConfiguredProvider), isFalse);
    });
  });

  group('the connector', () {
    test('carries the client id and the callback scheme', () async {
      final container = await integrationsContainer(
        config: const AppConfig(
          apiUrl: 'https://relay.test',
          rwgpsClientId: 'abcd',
          oauthScheme: 'velorki-dev',
        ),
        relay: FakeRelayClient(),
      );

      final connector = container.read(rwgpsConnectorProvider)!;

      expect(connector.clientId, 'abcd');
      expect(connector.callbackScheme, 'velorki-dev');
      expect(connector.flow.callbackScheme, 'velorki-dev');
      expect(connector.service, IntegrationService.rwgps);
    });

    test('a build without a relay has no connector', () async {
      final container = await integrationsContainer(
        config: const AppConfig(rwgpsClientId: 'abcd'),
      );
      expect(container.read(rwgpsConnectorProvider), isNull);
    });

    test('a build without a client id has no connector', () async {
      final container = await integrationsContainer(
        config: const AppConfig(apiUrl: 'https://relay.test'),
        relay: FakeRelayClient(),
      );
      expect(container.read(rwgpsConnectorProvider), isNull);
    });

    test('a connector appears once a relay URL is configured', () async {
      final container = await integrationsContainer(
        config: const AppConfig(rwgpsClientId: 'abcd'),
      );
      expect(container.read(rwgpsConnectorProvider), isNull);

      await container
          .read(serverOverridesProvider.notifier)
          .setApiUrl('https://my-own-relay.test');

      expect(container.read(rwgpsConnectorProvider), isNotNull);
    });

    test('reading the new user carries the token by hand', () async {
      late final FakeApiAdapter adapter;
      final container = await _connectedContainer(
        extraOverrides: <Override>[
          rwgpsBareDioProvider.overrideWithValue(() => dioWith(adapter)),
        ],
      );
      adapter = FakeApiAdapter(
        (options) => FakeResponse.json(<String, Object?>{
          'user': <String, Object?>{'id': 7, 'name': 'Steffen'},
        }),
      );

      final user = await container
          .read(rwgpsConnectorProvider)!
          .readUser('brand-new');

      expect(user!.name, 'Steffen');
      expect(adapter.requests.single.path, contains('/users/current.json'));
      // The interceptor cannot see a token that is not stored yet, so the
      // header has to come from the call itself.
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer brand-new',
      );
      // The throwaway client is closed again.
      expect(adapter.closes, 1);
    });

    test('a user lookup that fails still closes its client', () async {
      late final FakeApiAdapter adapter;
      final container = await _connectedContainer(
        extraOverrides: <Override>[
          rwgpsBareDioProvider.overrideWithValue(() => dioWith(adapter)),
        ],
      );
      adapter = FakeApiAdapter(
        (options) => FakeResponse.json(<String, Object?>{}, status: 500),
      );

      await expectLater(
        container.read(rwgpsConnectorProvider)!.readUser('brand-new'),
        throwsA(isA<IntegrationException>()),
      );
      // The connector catches this and connects anyway; see
      // connectors_test.dart. What matters here is that the throwaway client
      // is not leaked when the call fails.
      expect(adapter.closes, 1);
    });
  });

  group('the dio Ride with GPS is talked to over', () {
    test('identifies the app and asks for JSON', () async {
      final container = await _connectedContainer();
      final options = container.read(rwgpsDioProvider).options;

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
        (options) =>
            FakeResponse.json(<String, Object?>{'routes': const <Object?>[]}),
      );

      await container.read(rwgpsClientProvider).listRoutes();

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer stored-access',
      );
    });

    test('an expired token is sent anyway, because nothing can renew '
        'it', () async {
      final container = await _connectedContainer(
        account: _connected(
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );
      final adapter = _intercept(
        container,
        (options) =>
            FakeResponse.json(<String, Object?>{'routes': const <Object?>[]}),
      );

      await container.read(rwgpsClientProvider).listRoutes();

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer stored-access',
      );
    });

    test('a 401 is retried once with the same token and then given '
        'up on', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{}, status: 401),
      );

      final e = await integrationFailure(
        () => container.read(rwgpsClientProvider).listRoutes(),
      );

      expect(e.failure, IntegrationFailure.notConnected);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer stored-access',
      );
    });

    test('an error that is not a 401 is passed through untouched', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{}, status: 500),
      );

      final e = await integrationFailure(
        () => container.read(rwgpsClientProvider).listRoutes(),
      );

      expect(e.failure, IntegrationFailure.serviceError);
      expect(adapter.requests, hasLength(1));
    });

    test('a request without a connected account never flies', () async {
      final container = await integrationsContainer(relay: FakeRelayClient());
      await container.read(connectedAccountsProvider.future);
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{}),
      );

      final e = await integrationFailure(
        () => container.read(rwgpsClientProvider).listRoutes(),
      );

      expect(e.failure, IntegrationFailure.notConnected);
      expect(adapter.requests, isEmpty);
    });

    test('the client is closed when the container goes away', () async {
      final container = await _connectedContainer();
      final adapter = _intercept(
        container,
        (options) => FakeResponse.json(<String, Object?>{}),
      );

      container.dispose();

      expect(adapter.closes, 1);
    });

    test('is the dio the client was built on', () async {
      final container = await _connectedContainer();
      expect(
        container.read(rwgpsClientProvider).dio,
        same(container.read(rwgpsDioProvider)),
      );
    });
  });

  group('the token source', () {
    test('hands back the stored account unchanged, expired or not', () async {
      final expired = _connected(
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final container = await _connectedContainer(account: expired);

      final source = container.read(rwgpsTokenSourceProvider);

      expect(source.service, IntegrationService.rwgps);
      expect(await source.accessToken(forceRefresh: true), 'stored-access');
    });

    test('a refresh of an account that has a refresh token is a '
        'no-op', () async {
      // Ride with GPS tokens do not expire and the relay has no refresh
      // endpoint, so the source hands the same account straight back.
      final container = await _connectedContainer(
        account: _connected(
          refreshToken: 'stored-refresh',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );

      final account = await container
          .read(rwgpsTokenSourceProvider)
          .account(forceRefresh: true);

      expect(account.accessToken, 'stored-access');
      expect(account.refreshToken, 'stored-refresh');
    });

    test('reports that nothing is connected rather than throwing', () async {
      final container = await integrationsContainer(relay: FakeRelayClient());

      final e = await integrationFailure(
        () => container.read(rwgpsTokenSourceProvider).accessToken(),
      );
      expect(e.failure, IntegrationFailure.notConnected);
    });
  });

  test('the base options are the ones both clients share', () {
    final options = rwgpsBaseOptions();
    expect(options.connectTimeout, const Duration(seconds: 20));
    expect(options.receiveTimeout, const Duration(seconds: 60));
    expect(options.sendTimeout, const Duration(minutes: 2));
    expect(options.headers['Accept'], 'application/json');
  });

  test('the bare client identifies the app too', () async {
    final container = await integrationsContainer(relay: FakeRelayClient());
    // Nothing overrides the factory, so the connector really would build a
    // client of its own.
    expect(container.read(rwgpsBareDioProvider), same(buildRwgpsBareDio));

    final dio = buildRwgpsBareDio();
    addTearDown(dio.close);
    expect(dio.options.headers['User-Agent'], velorkiUserAgent);
    expect(dio.options.headers['Accept'], 'application/json');
  });

  test('the relay is never asked to refresh a Ride with GPS token', () async {
    final relayClient = FakeRelayClient();
    final container = await integrationsContainer(
      relay: relayClient,
      accounts: <IntegrationService, ConnectedAccount>{
        IntegrationService.rwgps: _connected(
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      },
    );
    await container.read(connectedAccountsProvider.future);
    _intercept(
      container,
      (options) =>
          FakeResponse.json(<String, Object?>{'routes': const <Object?>[]}),
    );

    await container.read(rwgpsClientProvider).listRoutes();

    expect(relayClient.refreshedWith, isEmpty);
  });
}
