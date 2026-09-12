import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/oauth_flow.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_auth.dart';
import 'package:velorki/features/integrations/strava/data/strava_auth.dart';

import 'support/fakes.dart';

final Uri _redirect = Uri.parse('velorki://oauth/strava');

OAuthFlow _flow({
  required FakeWebAuthenticator authenticator,
  FakeAppLauncher? launcher,
  Stream<Uri>? deepLinks,
}) => OAuthFlow(
  callbackScheme: 'velorki',
  deepLinks: deepLinks ?? const Stream<Uri>.empty(),
  authenticator: authenticator,
  launcher: launcher ?? FakeAppLauncher(),
  appToAppTimeout: const Duration(milliseconds: 200),
);

void main() {
  group('authorize URLs', () {
    test('Strava web and app-to-app carry the same parameters', () {
      final web = StravaAuth.webAuthorizeUrl(
        clientId: '1234',
        redirectUri: _redirect,
      );
      expect(web.origin, 'https://www.strava.com');
      expect(web.path, '/oauth/mobile/authorize');
      expect(web.queryParameters, <String, String>{
        'client_id': '1234',
        'redirect_uri': 'velorki://oauth/strava',
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': 'read,activity:write,activity:read',
      });

      final app = StravaAuth.appAuthorizeUrl(
        clientId: '1234',
        redirectUri: _redirect,
      );
      expect(app.scheme, 'strava');
      expect(app.host, 'oauth');
      expect(app.path, '/mobile/authorize');
      expect(app.queryParameters, web.queryParameters);
    });

    test('Ride with GPS has no scope and no approval prompt', () {
      final url = RwgpsAuth.authorizeUrl(
        clientId: 'abcd',
        redirectUri: Uri.parse('velorki://oauth/rwgps'),
      );
      expect(url.origin, 'https://ridewithgps.com');
      expect(url.path, '/oauth/authorize');
      expect(url.queryParameters, <String, String>{
        'client_id': 'abcd',
        'redirect_uri': 'velorki://oauth/rwgps',
        'response_type': 'code',
      });
    });
  });

  group('callback parsing', () {
    test('reads the code and the granted scopes', () {
      final callback = OAuthFlow.callbackOf(
        Uri.parse(
          'velorki://oauth/strava?state=&code=abc123'
          '&scope=read,activity:write,activity:read',
        ),
      );
      expect(callback.code, 'abc123');
      expect(callback.scopes, <String>[
        'read',
        'activity:write',
        'activity:read',
      ]);
    });

    test('access_denied is a cancellation, not a failure', () {
      final e = OAuthFlow.authorizationCodeOf;
      expect(
        () => e(Uri.parse('velorki://oauth/strava?error=access_denied')),
        throwsA(
          isA<IntegrationException>().having(
            (e) => e.failure,
            'failure',
            IntegrationFailure.cancelled,
          ),
        ),
      );
    });

    test('another error is a service error', () {
      expect(
        () => OAuthFlow.authorizationCodeOf(
          Uri.parse('velorki://oauth/strava?error=server_error'),
        ),
        throwsA(
          isA<IntegrationException>().having(
            (e) => e.failure,
            'failure',
            IntegrationFailure.serviceError,
          ),
        ),
      );
    });

    test('a callback without a code is a service error', () {
      expect(
        () =>
            OAuthFlow.authorizationCodeOf(Uri.parse('velorki://oauth/strava')),
        throwsA(isA<IntegrationException>()),
      );
    });

    test('only the matching redirect belongs to the flow', () {
      expect(
        OAuthFlow.matchesRedirect(
          Uri.parse('velorki://oauth/strava?code=1'),
          _redirect,
        ),
        isTrue,
      );
      expect(
        OAuthFlow.matchesRedirect(
          Uri.parse('velorki://oauth/strava/?code=1'),
          _redirect,
        ),
        isTrue,
      );
      expect(
        OAuthFlow.matchesRedirect(
          Uri.parse('velorki://oauth/rwgps?code=1'),
          _redirect,
        ),
        isFalse,
      );
      expect(
        OAuthFlow.matchesRedirect(Uri.parse('velorki://s/abc'), _redirect),
        isFalse,
      );
    });
  });

  group('running the flow', () {
    test('the web session answers with the code', () async {
      final authenticator = FakeWebAuthenticator(
        callback: Uri.parse('velorki://oauth/strava?code=web-code'),
      );
      final launcher = FakeAppLauncher();
      final flow = _flow(authenticator: authenticator, launcher: launcher);

      final callback = await flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        redirectUri: _redirect,
      );

      expect(callback.code, 'web-code');
      expect(authenticator.opened, hasLength(1));
      expect(launcher.launched, isEmpty);
    });

    test('the installed app is tried first and answers by deep link', () async {
      final deepLinks = StreamController<Uri>.broadcast();
      addTearDown(deepLinks.close);
      final authenticator = FakeWebAuthenticator();
      final launcher = FakeAppLauncher(canOpen: true);
      final flow = _flow(
        authenticator: authenticator,
        launcher: launcher,
        deepLinks: deepLinks.stream,
      );

      final result = flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        appAuthorizeUrl: Uri.parse('strava://oauth/mobile/authorize'),
        redirectUri: _redirect,
      );
      await Future<void>.delayed(Duration.zero);
      deepLinks.add(Uri.parse('velorki://oauth/strava?code=app-code'));

      expect((await result).code, 'app-code');
      expect(launcher.launched.single.scheme, 'strava');
      // The web page was never opened.
      expect(authenticator.opened, isEmpty);
    });

    test('no installed app falls back to the web session', () async {
      final authenticator = FakeWebAuthenticator(
        callback: Uri.parse('velorki://oauth/strava?code=fallback'),
      );
      final launcher = FakeAppLauncher();
      final flow = _flow(authenticator: authenticator, launcher: launcher);

      final callback = await flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        appAuthorizeUrl: Uri.parse('strava://oauth/mobile/authorize'),
        redirectUri: _redirect,
      );

      expect(callback.code, 'fallback');
      expect(launcher.asked, hasLength(1));
      expect(launcher.launched, isEmpty);
      expect(authenticator.opened, hasLength(1));
    });

    test('a deep link wins when the web session never reports back', () async {
      final deepLinks = StreamController<Uri>.broadcast();
      addTearDown(deepLinks.close);
      final flow = _flow(
        authenticator: FakeWebAuthenticator(),
        deepLinks: deepLinks.stream,
      );

      final result = flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        redirectUri: _redirect,
      );
      await Future<void>.delayed(Duration.zero);
      deepLinks.add(Uri.parse('velorki://s/other'));
      deepLinks.add(Uri.parse('velorki://oauth/strava?code=late'));

      expect((await result).code, 'late');
    });

    test(
      'an app-to-app flow that never comes back is a cancellation',
      () async {
        final deepLinks = StreamController<Uri>.broadcast();
        addTearDown(deepLinks.close);
        final flow = _flow(
          authenticator: FakeWebAuthenticator(),
          launcher: FakeAppLauncher(canOpen: true),
          deepLinks: deepLinks.stream,
        );

        final e = await integrationFailure(
          () => flow.authorize(
            webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
            appAuthorizeUrl: Uri.parse('strava://oauth/mobile/authorize'),
            redirectUri: _redirect,
          ),
        );
        expect(e.failure, IntegrationFailure.cancelled);
      },
    );

    test('a dismissed browser is reported as cancelled', () async {
      final flow = _flow(
        authenticator: FakeWebAuthenticator(
          failure: const IntegrationException.cancelled(),
        ),
      );
      final e = await integrationFailure(
        () => flow.authorize(
          webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
          redirectUri: _redirect,
        ),
      );
      expect(e.failure, IntegrationFailure.cancelled);
    });
  });
}
