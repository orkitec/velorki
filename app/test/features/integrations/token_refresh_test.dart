import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/data/oauth_token_source.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/strava/data/strava_connector.dart';
import 'package:velorki_api/velorki_api.dart' as relay;

import 'support/fake_dio.dart';
import 'support/fakes.dart';

DateTime _now = DateTime.utc(2026, 9, 12, 12);

ConnectedAccount _account({required DateTime expiresAt}) => ConnectedAccount(
  service: IntegrationService.strava,
  accessToken: 'old-access',
  refreshToken: 'old-refresh',
  expiresAt: expiresAt,
  athleteId: '42',
  athleteName: 'Steffen',
  scopes: const <String>['read'],
);

relay.StravaTokens _freshTokens() => relay.StravaTokens(
  accessToken: 'new-access',
  refreshToken: 'new-refresh',
  expiresAt: _now.add(const Duration(hours: 6)).millisecondsSinceEpoch ~/ 1000,
);

/// What the relay client would put on: its bearer and the client id.
Map<String, String> _relayHeaders() => const <String, String>{
  'Authorization': 'Bearer user-1',
  'X-Velorki-Client': 'test/1',
};

void main() {
  late InMemorySecureKeyValueStore store;
  late ConnectedAccountsRepository repository;
  late FakeRelayClient relayClient;

  setUp(() {
    store = InMemorySecureKeyValueStore();
    repository = ConnectedAccountsRepository(store);
    relayClient = FakeRelayClient(refreshedStravaTokens: _freshTokens());
  });

  OAuthTokenSource source() => OAuthTokenSource(
    service: IntegrationService.strava,
    repository: repository,
    clock: () => _now,
    refresher: (expiring) =>
        refreshStravaThroughRelay(expiring, relayClient: relayClient),
  );

  test('a token that is still good is used unchanged', () async {
    await repository.save(
      _account(expiresAt: _now.add(const Duration(hours: 1))),
    );

    expect(await source().accessToken(), 'old-access');
    expect(relayClient.refreshedWith, isEmpty);
  });

  test('a token inside the 60 second leeway is refreshed first', () async {
    await repository.save(
      _account(expiresAt: _now.add(const Duration(seconds: 30))),
    );

    expect(await source().accessToken(), 'new-access');
    expect(relayClient.refreshedWith, <String>['old-refresh']);

    // The rotated refresh token was written back, and the athlete kept.
    final stored = await repository.read(IntegrationService.strava);
    expect(stored!.refreshToken, 'new-refresh');
    expect(stored.athleteName, 'Steffen');
    expect(stored.scopes, <String>['read']);
  });

  test('two callers at once spend the refresh token only once', () async {
    await repository.save(
      _account(expiresAt: _now.subtract(const Duration(minutes: 5))),
    );
    final tokens = source();

    final results = await Future.wait<String>(<Future<String>>[
      tokens.accessToken(),
      tokens.accessToken(),
    ]);

    expect(results, <String>['new-access', 'new-access']);
    expect(relayClient.refreshedWith, hasLength(1));
  });

  test('nothing connected is reported, not thrown as a state error', () async {
    final e = await integrationFailure(() => source().accessToken());
    expect(e.failure, IntegrationFailure.notConnected);
  });

  test('a relay that refuses the refresh surfaces its message', () async {
    await repository.save(
      _account(expiresAt: _now.subtract(const Duration(minutes: 5))),
    );
    relayClient.failure = const relay.RelayException(
      relay.RelayError(
        code: relay.RelayErrorCode.notEntitled,
        message: 'no entitlement',
      ),
    );

    final e = await integrationFailure(() => source().accessToken());
    expect(e.failure, IntegrationFailure.relayUnavailable);
  });

  group('the dio interceptor', () {
    test('puts the wrapped token and the relay\'s headers on the '
        'request', () async {
      await repository.save(
        _account(expiresAt: _now.add(const Duration(hours: 1))),
      );
      final adapter = FakeApiAdapter(
        (options) => FakeResponse.json(<String, Object?>{'ok': true}),
      );
      final dio = dioWith(adapter);
      dio.interceptors.add(
        OAuthTokenInterceptor(
          tokens: source(),
          dio: () => dio,
          relayHeaders: _relayHeaders,
        ),
      );

      await dio.get<dynamic>('https://www.strava.com/api/v3/athlete');

      final headers = adapter.requests.single.headers;
      expect(headers['X-Velorki-Token'], 'old-access');
      // The relay's bearer is the app user id, never the service token.
      expect(headers['Authorization'], 'Bearer user-1');
      expect(headers['X-Velorki-Client'], 'test/1');
    });

    test('a re-wrapped token in the answer replaces the stored one', () async {
      await repository.save(
        _account(expiresAt: _now.add(const Duration(hours: 1))),
      );
      final adapter = FakeApiAdapter(
        (options) => FakeResponse.json(
          <String, Object?>{'ok': true},
          headers: <String, String>{'X-Velorki-Token-Rewrapped': 'v1.k2.new'},
        ),
      );
      final dio = dioWith(adapter);
      dio.interceptors.add(
        OAuthTokenInterceptor(
          tokens: source(),
          dio: () => dio,
          relayHeaders: _relayHeaders,
        ),
      );

      await dio.get<dynamic>('https://www.strava.com/api/v3/athlete');

      final stored = await repository.read(IntegrationService.strava);
      expect(stored!.accessToken, 'v1.k2.new');
      // Only the token changes; the rest of the account is kept.
      expect(stored.refreshToken, 'old-refresh');
      expect(stored.athleteId, '42');
    });

    test('a 401 in the relay\'s own words is not retried', () async {
      await repository.save(
        _account(expiresAt: _now.add(const Duration(hours: 1))),
      );
      var calls = 0;
      final adapter = FakeApiAdapter((options) {
        calls++;
        return FakeResponse.json(<String, Object?>{
          'error': <String, Object?>{
            'code': 'not_entitled',
            'message': 'An active Velorki subscription is required.',
          },
        }, status: 401);
      });
      final dio = dioWith(adapter);
      dio.interceptors.add(
        OAuthTokenInterceptor(
          tokens: source(),
          dio: () => dio,
          relayHeaders: _relayHeaders,
        ),
      );

      await expectLater(
        dio.get<dynamic>('https://www.strava.com/api/v3/athlete'),
        throwsA(isA<DioException>()),
      );
      // Plus lapsed: a fresh token would get the same answer.
      expect(calls, 1);
      expect(relayClient.refreshedWith, isEmpty);
    });

    test(
      'refreshes before the call when the token is about to expire',
      () async {
        await repository.save(
          _account(expiresAt: _now.add(const Duration(seconds: 10))),
        );
        final adapter = FakeApiAdapter(
          (options) => FakeResponse.json(<String, Object?>{'ok': true}),
        );
        final dio = dioWith(adapter);
        dio.interceptors.add(
          OAuthTokenInterceptor(
            tokens: source(),
            dio: () => dio,
            relayHeaders: _relayHeaders,
          ),
        );

        await dio.get<dynamic>('https://www.strava.com/api/v3/athlete');

        expect(
          adapter.requests.single.headers['X-Velorki-Token'],
          'new-access',
        );
        expect(relayClient.refreshedWith, hasLength(1));
      },
    );

    test('a 401 triggers one forced refresh and one retry', () async {
      await repository.save(
        _account(expiresAt: _now.add(const Duration(hours: 1))),
      );
      var calls = 0;
      final adapter = FakeApiAdapter((options) {
        calls++;
        return calls == 1
            ? FakeResponse.json(<String, Object?>{
                'message': 'Authorization Error',
              }, status: 401)
            : FakeResponse.json(<String, Object?>{'id': 42});
      });
      final dio = dioWith(adapter);
      dio.interceptors.add(
        OAuthTokenInterceptor(
          tokens: source(),
          dio: () => dio,
          relayHeaders: _relayHeaders,
        ),
      );

      final response = await dio.get<dynamic>(
        'https://www.strava.com/api/v3/athlete',
      );

      expect(calls, 2);
      expect((response.data as Map<String, Object?>)['id'], 42);
      expect(adapter.requests.last.headers['X-Velorki-Token'], 'new-access');
    });

    test('a second 401 is not retried again', () async {
      await repository.save(
        _account(expiresAt: _now.add(const Duration(hours: 1))),
      );
      var calls = 0;
      final adapter = FakeApiAdapter((options) {
        calls++;
        return FakeResponse.json(<String, Object?>{}, status: 401);
      });
      final dio = dioWith(adapter);
      dio.interceptors.add(
        OAuthTokenInterceptor(
          tokens: source(),
          dio: () => dio,
          relayHeaders: _relayHeaders,
        ),
      );

      await expectLater(
        dio.get<dynamic>('https://www.strava.com/api/v3/athlete'),
        throwsA(isA<DioException>()),
      );
      expect(calls, 2);
    });

    test(
      'a request without a connected account is rejected before it flies',
      () async {
        final adapter = FakeApiAdapter(
          (options) => FakeResponse.json(<String, Object?>{}),
        );
        final dio = dioWith(adapter);
        dio.interceptors.add(
          OAuthTokenInterceptor(
            tokens: source(),
            dio: () => dio,
            relayHeaders: _relayHeaders,
          ),
        );

        await expectLater(
          dio.get<dynamic>('https://www.strava.com/api/v3/athlete'),
          throwsA(
            isA<DioException>().having(
              (e) => e.error,
              'error',
              isA<IntegrationException>().having(
                (e) => e.failure,
                'failure',
                IntegrationFailure.notConnected,
              ),
            ),
          ),
        );
        expect(adapter.requests, isEmpty);
      },
    );
  });
}
