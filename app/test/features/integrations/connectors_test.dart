import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/oauth_flow.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_connector.dart';
import 'package:velorki/features/integrations/rwgps/domain/rwgps_models.dart';
import 'package:velorki/features/integrations/strava/data/strava_connector.dart';
import 'package:velorki_api/velorki_api.dart' as relay;

import 'support/fakes.dart';

final DateTime _now = DateTime.utc(2026, 9, 12, 12);

relay.StravaTokens _tokens() => relay.StravaTokens(
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresAt: _now.add(const Duration(hours: 6)).millisecondsSinceEpoch ~/ 1000,
  athlete: <String, Object?>{
    'id': 42,
    'firstname': 'Steffen',
    'lastname': 'Römer',
  },
);

OAuthFlow _flow(FakeWebAuthenticator authenticator, FakeAppLauncher launcher) =>
    OAuthFlow(
      callbackScheme: 'velorki',
      deepLinks: const Stream<Uri>.empty(),
      authenticator: authenticator,
      launcher: launcher,
    );

void main() {
  group('StravaConnector', () {
    late FakeWebAuthenticator authenticator;
    late FakeAppLauncher launcher;
    late FakeRelayClient relayClient;
    final revoked = <String>[];

    setUp(() {
      revoked.clear();
      authenticator = FakeWebAuthenticator(
        callback: Uri.parse(
          'velorki://oauth/strava?code=the-code'
          '&scope=read,activity:write,activity:read',
        ),
      );
      launcher = FakeAppLauncher();
      relayClient = FakeRelayClient(stravaTokens: _tokens());
    });

    StravaConnector connector({bool preferAppToApp = false}) => StravaConnector(
      flow: _flow(authenticator, launcher),
      relayClient: relayClient,
      clientId: '1234',
      callbackScheme: 'velorki',
      preferAppToApp: preferAppToApp,
      deauthorize: (account) async => revoked.add(account.accessToken),
    );

    test(
      'exchanges the code through the relay and builds the account',
      () async {
        final account = await connector().connect();

        expect(authenticator.opened.single.origin, 'https://www.strava.com');
        expect(relayClient.exchangedCodes, <String>['the-code']);
        expect(relayClient.redirectUris, <String>['velorki://oauth/strava']);
        expect(account.service, IntegrationService.strava);
        expect(account.accessToken, 'access');
        expect(account.refreshToken, 'refresh');
        expect(account.athleteId, '42');
        expect(account.athleteName, 'Steffen Römer');
        expect(account.scopes, <String>[
          'read',
          'activity:write',
          'activity:read',
        ]);
        expect(account.expiresAt, _now.add(const Duration(hours: 6)));
      },
    );

    test('offers the installed app first when asked to', () async {
      launcher.canOpen = false;
      await connector(preferAppToApp: true).connect();
      expect(launcher.asked.single.scheme, 'strava');
    });

    test('does not even ask about the app on Android', () async {
      await connector().connect();
      expect(launcher.asked, isEmpty);
    });

    test('a relay that refuses is reported as such', () async {
      relayClient.failure = const relay.RelayException(
        relay.RelayError(
          code: relay.RelayErrorCode.rateLimited,
          message: 'slow down',
          retryAfterS: 30,
        ),
      );

      final e = await integrationFailure(() => connector().connect());
      expect(e.failure, IntegrationFailure.rateLimited);
      expect(e.retryAfter, const Duration(seconds: 30));
    });

    test('revoke never throws, so a disconnect always finishes', () async {
      final connect = StravaConnector(
        flow: _flow(authenticator, launcher),
        relayClient: relayClient,
        clientId: '1234',
        callbackScheme: 'velorki',
        deauthorize: (_) async => throw StateError('Strava is down'),
      );

      await connect.revoke(
        const ConnectedAccount(
          service: IntegrationService.strava,
          accessToken: 'a',
        ),
      );
    });

    test('an athlete without a real name falls back to the username', () {
      expect(
        StravaConnector.athleteNameOf(<String, Object?>{
          'username': 'velorider',
        }),
        'velorider',
      );
      expect(StravaConnector.athleteNameOf(null), isNull);
    });

    test('a refresh replaces the whole rotated token set', () {
      const before = ConnectedAccount(
        service: IntegrationService.strava,
        accessToken: 'old',
        refreshToken: 'old-refresh',
        athleteId: '42',
        athleteName: 'Steffen',
        scopes: <String>['read'],
      );
      final after = applyStravaRefresh(
        before,
        relay.StravaTokens(
          accessToken: 'new',
          refreshToken: 'new-refresh',
          expiresAt: 1790000000,
        ),
      );

      expect(after.accessToken, 'new');
      expect(after.refreshToken, 'new-refresh');
      expect(after.athleteName, 'Steffen');
      expect(after.scopes, <String>['read']);
    });
  });

  group('RwgpsConnector', () {
    test(
      'exchanges the code and reads the user for the settings tile',
      () async {
        final authenticator = FakeWebAuthenticator(
          callback: Uri.parse('velorki://oauth/rwgps?code=rw-code'),
        );
        final relayClient = FakeRelayClient(
          rwgpsTokens: const relay.RwgpsTokens(accessToken: 'rw-access'),
        );
        final connector = RwgpsConnector(
          flow: _flow(authenticator, FakeAppLauncher()),
          relayClient: relayClient,
          clientId: 'abcd',
          callbackScheme: 'velorki',
          readUser: (token) async => RwgpsUser(id: '1', name: 'Steffen $token'),
          revokeAt: (_) async {},
        );

        final account = await connector.connect();

        expect(authenticator.opened.single.origin, 'https://ridewithgps.com');
        expect(relayClient.exchangedCodes, <String>['rw-code']);
        expect(relayClient.redirectUris, <String>['velorki://oauth/rwgps']);
        expect(account.accessToken, 'rw-access');
        expect(account.refreshToken, isNull);
        expect(account.expiresAt, isNull);
        expect(account.athleteId, '1');
        expect(account.athleteName, 'Steffen rw-access');
      },
    );

    test('a user lookup that fails still yields a usable connection', () async {
      final connector = RwgpsConnector(
        flow: _flow(
          FakeWebAuthenticator(
            callback: Uri.parse('velorki://oauth/rwgps?code=rw-code'),
          ),
          FakeAppLauncher(),
        ),
        relayClient: FakeRelayClient(
          rwgpsTokens: const relay.RwgpsTokens(accessToken: 'rw-access'),
        ),
        clientId: 'abcd',
        callbackScheme: 'velorki',
        readUser: (_) async => throw StateError('no'),
        revokeAt: (_) async {},
      );

      final account = await connector.connect();
      expect(account.accessToken, 'rw-access');
      expect(account.athleteName, isNull);
    });

    test('revoke goes to the relay and never throws', () async {
      final revoked = <String>[];
      RwgpsConnector connector(Future<void> Function(ConnectedAccount) at) =>
          RwgpsConnector(
            flow: _flow(FakeWebAuthenticator(), FakeAppLauncher()),
            relayClient: FakeRelayClient(),
            clientId: 'abcd',
            callbackScheme: 'velorki',
            readUser: (_) async => null,
            revokeAt: at,
          );
      const account = ConnectedAccount(
        service: IntegrationService.rwgps,
        accessToken: 'rw',
      );

      await connector((a) async => revoked.add(a.accessToken)).revoke(account);
      expect(revoked, <String>['rw']);

      // The relay being down does not keep the token on the phone.
      await connector((_) async => throw StateError('down')).revoke(account);
    });
  });
}
