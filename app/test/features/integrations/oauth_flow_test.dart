import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/oauth_flow.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_auth.dart';
import 'package:velorki/features/integrations/strava/data/strava_auth.dart';

import 'support/fakes.dart';
import 'support/pump.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('a state is sent only when one is asked for', () {
      expect(
        StravaAuth.webAuthorizeUrl(
          clientId: '1234',
          redirectUri: _redirect,
          state: 'nonce-1',
        ).queryParameters['state'],
        'nonce-1',
      );
      expect(
        StravaAuth.appAuthorizeUrl(
          clientId: '1234',
          redirectUri: _redirect,
          state: 'nonce-1',
        ).queryParameters['state'],
        'nonce-1',
      );
      expect(
        RwgpsAuth.authorizeUrl(
          clientId: 'abcd',
          redirectUri: Uri.parse('velorki://oauth/rwgps'),
          state: 'nonce-1',
        ).queryParameters['state'],
        'nonce-1',
      );
    });

    test('neither service is asked for PKCE', () {
      // The client secret lives in the relay and the code is exchanged from
      // there, so there is no verifier the app could keep. What binds a
      // callback to this app is the custom scheme and the redirect path.
      final parameters = <String>{
        ...StravaAuth.webAuthorizeUrl(
          clientId: '1234',
          redirectUri: _redirect,
        ).queryParameters.keys,
        ...RwgpsAuth.authorizeUrl(
          clientId: 'abcd',
          redirectUri: Uri.parse('velorki://oauth/rwgps'),
        ).queryParameters.keys,
      };
      expect(parameters, isNot(contains('code_challenge')));
      expect(parameters, isNot(contains('code_challenge_method')));
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
      // The token must never reach a log line.
      expect(callback.toString(), isNot(contains('abc123')));
      expect(callback.toString(), contains('activity:write'));
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

    test('an app-to-app launch the platform refuses falls back to the '
        'web session', () async {
      final authenticator = FakeWebAuthenticator(
        callback: Uri.parse('velorki://oauth/strava?code=after-refusal'),
      );
      // The platform knows the app, but handing the URL over does not work.
      final launcher = FakeAppLauncher(canOpen: true, opens: false);
      final flow = _flow(authenticator: authenticator, launcher: launcher);

      final callback = await flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        appAuthorizeUrl: Uri.parse('strava://oauth/mobile/authorize'),
        redirectUri: _redirect,
      );

      expect(callback.code, 'after-refusal');
      expect(launcher.launched, hasLength(1));
      expect(authenticator.opened, hasLength(1));
    });

    test('a rider who denies access ends the flow as cancelled', () async {
      final flow = _flow(
        authenticator: FakeWebAuthenticator(
          callback: Uri.parse('velorki://oauth/strava?error=access_denied'),
        ),
      );

      final e = await integrationFailure(
        () => flow.authorize(
          webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
          redirectUri: _redirect,
        ),
      );
      expect(e.failure, IntegrationFailure.cancelled);
      expect(e.message, contains('nothing was connected'));
    });

    test('a service that refuses the authorisation says so', () async {
      final flow = _flow(
        authenticator: FakeWebAuthenticator(
          callback: Uri.parse('velorki://oauth/strava?error=server_error'),
        ),
      );

      final e = await integrationFailure(
        () => flow.authorize(
          webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
          redirectUri: _redirect,
        ),
      );
      expect(e.failure, IntegrationFailure.serviceError);
      expect(e.message, contains('server_error'));
    });

    test('a redirect that carries no code at all is a service error', () async {
      final flow = _flow(
        authenticator: FakeWebAuthenticator(
          callback: Uri.parse('velorki://oauth/strava'),
        ),
      );

      final e = await integrationFailure(
        () => flow.authorize(
          webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
          redirectUri: _redirect,
        ),
      );
      expect(e.failure, IntegrationFailure.serviceError);
    });

    test('a deep link for the other service does not end this flow', () async {
      final deepLinks = StreamController<Uri>.broadcast();
      addTearDown(deepLinks.close);
      final flow = _flow(
        authenticator: FakeWebAuthenticator(
          callback: Uri.parse('velorki://oauth/strava?code=web-code'),
          delay: const Duration(milliseconds: 20),
        ),
        deepLinks: deepLinks.stream,
      );

      final result = flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        redirectUri: _redirect,
      );
      await Future<void>.delayed(Duration.zero);
      deepLinks.add(Uri.parse('velorki://oauth/rwgps?code=wrong-service'));

      expect((await result).code, 'web-code');
    });

    test('a deep link that ended without a match does not end the '
        'flow', () async {
      // The web path closes the link stream without ever matching; that must
      // not race the browser to an answer.
      final flow = _flow(
        authenticator: FakeWebAuthenticator(
          callback: Uri.parse('velorki://oauth/strava?code=web-code'),
          delay: const Duration(milliseconds: 20),
        ),
        deepLinks: const Stream<Uri>.empty(),
      );

      final callback = await flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        redirectUri: _redirect,
      );
      expect(callback.code, 'web-code');
    });

    test('an app-to-app deep link that says access_denied is a '
        'cancellation', () async {
      final deepLinks = StreamController<Uri>.broadcast();
      addTearDown(deepLinks.close);
      final flow = _flow(
        authenticator: FakeWebAuthenticator(),
        launcher: FakeAppLauncher(canOpen: true),
        deepLinks: deepLinks.stream,
      );

      final result = flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        appAuthorizeUrl: Uri.parse('strava://oauth/mobile/authorize'),
        redirectUri: _redirect,
      );
      await Future<void>.delayed(Duration.zero);
      deepLinks.add(Uri.parse('velorki://oauth/strava?error=access_denied'));

      await expectLater(
        result,
        throwsA(
          isA<IntegrationException>().having(
            (e) => e.failure,
            'failure',
            IntegrationFailure.cancelled,
          ),
        ),
      );
    });
  });

  group('the links the flows listen on', () {
    test('a link the platform delivers reaches a flow', () async {
      final incoming = StreamController<Uri>.broadcast();
      addTearDown(incoming.close);
      final container = await integrationsContainer(deepLinks: incoming.stream);
      // Riverpod pauses a provider nobody listens to, and the republisher
      // only follows the platform stream while it is running.
      container.listen(oauthDeepLinksProvider, (_, _) {});
      final links = <Uri>[];
      container.read(oauthDeepLinksProvider).listen(links.add);

      incoming.add(Uri.parse('velorki://oauth/strava?code=1'));
      await Future<void>.delayed(Duration.zero);

      expect(links, <Uri>[Uri.parse('velorki://oauth/strava?code=1')]);
    });

    test('the same link is published once, not on every rebuild', () async {
      final incoming = StreamController<Uri>.broadcast();
      addTearDown(incoming.close);
      final container = await integrationsContainer(deepLinks: incoming.stream);
      // Riverpod pauses a provider nobody listens to, and the republisher
      // only follows the platform stream while it is running.
      container.listen(oauthDeepLinksProvider, (_, _) {});
      final links = <Uri>[];
      container.read(oauthDeepLinksProvider).listen(links.add);

      incoming.add(Uri.parse('velorki://oauth/strava?code=1'));
      await Future<void>.delayed(Duration.zero);
      incoming.add(Uri.parse('velorki://oauth/strava?code=1'));
      await Future<void>.delayed(Duration.zero);
      incoming.add(Uri.parse('velorki://oauth/rwgps?code=2'));
      await Future<void>.delayed(Duration.zero);

      expect(links, <Uri>[
        Uri.parse('velorki://oauth/strava?code=1'),
        Uri.parse('velorki://oauth/rwgps?code=2'),
      ]);
    });

    test('the stream is closed with the container', () async {
      final incoming = StreamController<Uri>.broadcast();
      addTearDown(incoming.close);
      final container = await integrationsContainer(deepLinks: incoming.stream);
      final stream = container.read(oauthDeepLinksProvider);

      container.dispose();

      await expectLater(stream, emitsDone);
    });

    test('the flow of a scheme is built once and reused', () async {
      final container = await integrationsContainer();

      final flow = container.read(oauthFlowProvider('velorki'));
      expect(flow.callbackScheme, 'velorki');
      expect(container.read(oauthFlowProvider('velorki')), same(flow));
      expect(
        container.read(oauthFlowProvider('velorki-dev')),
        isNot(same(flow)),
      );
      expect(
        container.read(oauthFlowProvider('velorki-dev')).callbackScheme,
        'velorki-dev',
      );
    });

    test('a link that arrives after the browser opened finishes the '
        'authorisation', () async {
      final incoming = StreamController<Uri>.broadcast();
      addTearDown(incoming.close);
      final container = await integrationsContainer(deepLinks: incoming.stream);
      container.listen(oauthDeepLinksProvider, (_, _) {});
      // Subscribing before anything opens is what keeps the callback of a
      // cold-started app from being lost.
      final flow = OAuthFlow(
        callbackScheme: 'velorki',
        deepLinks: container.read(oauthDeepLinksProvider),
        authenticator: FakeWebAuthenticator(),
        launcher: FakeAppLauncher(),
      );

      final result = flow.authorize(
        webAuthorizeUrl: Uri.parse('https://www.strava.com/oauth/x'),
        redirectUri: _redirect,
      );
      await Future<void>.delayed(Duration.zero);
      incoming.add(Uri.parse('velorki://oauth/strava?code=through-providers'));

      expect((await result).code, 'through-providers');
    });
  });

  group('the production web authenticator', () {
    const channel = MethodChannel('flutter_web_auth_2');
    const authenticator = FlutterWebAuthenticator();

    void answerWith(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    test('reports the URL the session was redirected to', () async {
      late Map<Object?, Object?> arguments;
      answerWith((call) async {
        arguments = call.arguments as Map<Object?, Object?>;
        return 'velorki://oauth/strava?code=from-the-session';
      });

      final callback = await authenticator.authenticate(
        url: Uri.parse('https://www.strava.com/oauth/mobile/authorize'),
        callbackUrlScheme: 'velorki',
      );

      expect(
        callback,
        Uri.parse('velorki://oauth/strava?code=from-the-session'),
      );
      expect(arguments['url'], 'https://www.strava.com/oauth/mobile/authorize');
      expect(arguments['callbackUrlScheme'], 'velorki');
    });

    test('a dismissed sheet is a cancellation', () async {
      // Both platforms report it with a CANCELED-ish code.
      answerWith((call) async => throw PlatformException(code: 'CANCELED'));

      final e = await integrationFailure(
        () => authenticator.authenticate(
          url: Uri.parse('https://www.strava.com/oauth/x'),
          callbackUrlScheme: 'velorki',
        ),
      );
      expect(e.failure, IntegrationFailure.cancelled);
    });

    test('a page that could not be opened says why', () async {
      answerWith(
        (call) async => throw PlatformException(
          code: 'NO_BROWSER',
          message: 'no browser installed',
        ),
      );

      final e = await integrationFailure(
        () => authenticator.authenticate(
          url: Uri.parse('https://www.strava.com/oauth/x'),
          callbackUrlScheme: 'velorki',
        ),
      );
      expect(e.failure, IntegrationFailure.serviceError);
      expect(e.message, contains('no browser installed'));
    });
  });

  group('the production app launcher', () {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    const launcher = UrlLauncherAppLauncher();
    final url = Uri.parse('strava://oauth/mobile/authorize');

    test('a platform without the plugin simply answers no', () async {
      expect(await launcher.canLaunch(url), isFalse);
      expect(await launcher.launch(url), isFalse);
    });

    test('a platform that knows the app says so', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      expect(await launcher.canLaunch(url), isTrue);
      expect(await launcher.launch(url), isTrue);
      expect(calls, <String>['canLaunch', 'launch']);
    });

    test('a platform that fails the call counts as no', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(code: 'BOOM'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      expect(await launcher.canLaunch(url), isFalse);
      expect(await launcher.launch(url), isFalse);
    });
  });
}
