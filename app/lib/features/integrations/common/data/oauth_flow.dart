import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../../import_export/data/incoming_file_service.dart';
import '../domain/integration_exception.dart';

final Logger _log = Logger('OAuthFlow');

/// Opens an authorisation page and waits for the redirect back.
///
/// An interface so tests can drive the whole flow without a browser:
/// `flutter test` has neither Custom Tabs nor `ASWebAuthenticationSession`.
abstract class WebAuthenticator {
  /// Opens [url] and completes with the callback URL the service redirected
  /// to, whose scheme is [callbackUrlScheme].
  ///
  /// Throws [IntegrationException] with [IntegrationFailure.cancelled] when
  /// the rider dismissed the page.
  Future<Uri> authenticate({
    required Uri url,
    required String callbackUrlScheme,
  });
}

/// The production [WebAuthenticator]: `flutter_web_auth_2`.
///
/// On Android that is a Chrome Custom Tab whose redirect is caught by
/// `com.linusu.flutter_web_auth_2.CallbackActivity`; on iOS it is an
/// `ASWebAuthenticationSession`, which keeps the session cookies of Safari so
/// an already signed-in rider only has to press "Authorize".
class FlutterWebAuthenticator implements WebAuthenticator {
  /// Creates the authenticator.
  const FlutterWebAuthenticator();

  @override
  Future<Uri> authenticate({
    required Uri url,
    required String callbackUrlScheme,
  }) async {
    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: callbackUrlScheme,
      );
    } on PlatformException catch (e) {
      // The plugin reports a dismissed sheet as CANCELED on both platforms.
      if (e.code.toUpperCase().contains('CANCEL')) {
        throw const IntegrationException.cancelled();
      }
      throw IntegrationException(
        IntegrationFailure.serviceError,
        'The authorisation page could not be opened: ${e.message ?? e.code}',
        cause: e,
      );
    }
    return Uri.parse(result);
  }
}

/// Opening a URL with another app, for the app-to-app flows.
abstract class AppLauncher {
  /// Whether the platform knows an app that handles [url].
  Future<bool> canLaunch(Uri url);

  /// Hands [url] to that app; `false` when nothing took it.
  Future<bool> launch(Uri url);
}

/// The production [AppLauncher]: `url_launcher`.
class UrlLauncherAppLauncher implements AppLauncher {
  /// Creates the launcher.
  const UrlLauncherAppLauncher();

  @override
  Future<bool> canLaunch(Uri url) async {
    try {
      return await launcher.canLaunchUrl(url);
    } on Object catch (e) {
      // A platform that refuses to answer counts as "no".
      _log.fine('canLaunchUrl($url) failed', e);
      return false;
    }
  }

  @override
  Future<bool> launch(Uri url) async {
    try {
      return await launcher.launchUrl(
        url,
        mode: launcher.LaunchMode.externalApplication,
      );
    } on Object catch (e) {
      _log.fine('launchUrl($url) failed', e);
      return false;
    }
  }
}

/// What the service sent back when it redirected.
class OAuthCallback {
  /// Creates a callback.
  const OAuthCallback({required this.code, required this.uri});

  /// The single-use authorisation code, already validated as present.
  final String code;

  /// The whole redirect URI, for the parameters only some services send.
  final Uri uri;

  /// The scopes the rider actually granted.
  ///
  /// Strava puts them in the callback as `scope=read,activity:write`; a
  /// service that sends none yields an empty list.
  List<String> get scopes => <String>[
    for (final scope in (uri.queryParameters['scope'] ?? '').split(','))
      if (scope.trim().isNotEmpty) scope.trim(),
  ];

  @override
  String toString() => 'OAuthCallback(scopes: $scopes)';
}

/// One OAuth authorisation, from the authorise URL to the `code`.
///
/// Two ways home, and the app needs both:
///
/// * **The web session.** `flutter_web_auth_2` opens the authorisation page
///   and *is itself* told about the redirect — a Custom Tab on Android, an
///   `ASWebAuthenticationSession` on iOS. This is the normal path, and the
///   only one for Ride with GPS.
/// * **The deep link.** Strava's iOS app-to-app flow (`strava://oauth/mobile/
///   authorize`) is opened with `url_launcher`, so there is no web session to
///   report anything: the Strava app sends the rider back with an ordinary
///   `velorki://oauth/strava?code=…` link, which arrives through `app_links`
///   on [IncomingFileService.deepLinks]. The same path catches the case where
///   the system decides to hand the redirect to the app rather than to the
///   session.
///
/// Both are subscribed before anything is opened, so a callback that arrives
/// while the app is still resuming is not lost.
class OAuthFlow {
  /// Creates a flow.
  ///
  /// [callbackScheme] is the custom scheme of the redirect URI, `velorki` in
  /// this app. [deepLinks] carries every non-file link the app receives.
  OAuthFlow({
    required this.callbackScheme,
    required this.deepLinks,
    this.authenticator = const FlutterWebAuthenticator(),
    this.launcher = const UrlLauncherAppLauncher(),
    this.appToAppTimeout = const Duration(minutes: 5),
  });

  /// The scheme the service redirects to.
  final String callbackScheme;

  /// How long to wait for an app-to-app callback before giving up.
  final Duration appToAppTimeout;

  /// Opens the authorisation page and reports the redirect.
  final WebAuthenticator authenticator;

  /// Hands an app-to-app URL to the installed partner app.
  final AppLauncher launcher;

  /// Every non-file link the app receives.
  final Stream<Uri> deepLinks;

  /// Runs the authorisation and returns what the service redirected with.
  ///
  /// [appAuthorizeUrl] is tried first when the platform knows an app for it;
  /// when it does not, or the launch fails, [webAuthorizeUrl] is opened in the
  /// web session instead. [redirectUri] is what both were told to come back
  /// to, and decides which deep links belong to this flow.
  ///
  /// Throws [IntegrationException].
  Future<OAuthCallback> authorize({
    required Uri webAuthorizeUrl,
    required Uri redirectUri,
    Uri? appAuthorizeUrl,
  }) async {
    // Subscribed before anything opens: on Android the app can be resumed by
    // the callback intent itself, and the link is then already on its way.
    //
    // A stream that ends without a matching link — the normal case on the web
    // path — must not end the race: it is turned into a future that simply
    // never completes, so the web session or the timeout decides.
    final callback = deepLinks
        .where((uri) => matchesRedirect(uri, redirectUri))
        .first
        .then<Uri>(
          (uri) => uri,
          onError: (Object _) => Completer<Uri>().future,
        );

    if (appAuthorizeUrl != null && await launcher.canLaunch(appAuthorizeUrl)) {
      _log.fine('trying app-to-app authorisation at $appAuthorizeUrl');
      if (await launcher.launch(appAuthorizeUrl)) {
        return callbackOf(
          await callback.timeout(
            appToAppTimeout,
            onTimeout: () => throw const IntegrationException.cancelled(
              'The authorisation was not completed.',
            ),
          ),
        );
      }
      _log.info('app-to-app launch refused; falling back to the web flow');
    }

    final web = authenticator.authenticate(
      url: webAuthorizeUrl,
      callbackUrlScheme: callbackScheme,
    );
    // Whichever answers first wins: some Android configurations deliver the
    // redirect to the app instead of to the Custom Tab session.
    return callbackOf(await Future.any(<Future<Uri>>[web, callback]));
  }

  /// Whether [uri] is the redirect of the flow that asked for [redirectUri].
  ///
  /// Scheme, host and path have to match; the query is where the answer is.
  static bool matchesRedirect(Uri uri, Uri redirectUri) =>
      uri.scheme == redirectUri.scheme &&
      uri.host == redirectUri.host &&
      _normalizePath(uri.path) == _normalizePath(redirectUri.path);

  /// Reads a callback [uri] into an [OAuthCallback].
  ///
  /// Throws [IntegrationException] when the service said `error=` instead,
  /// and when there is no code at all.
  static OAuthCallback callbackOf(Uri uri) =>
      OAuthCallback(code: authorizationCodeOf(uri), uri: uri);

  /// Reads the `code` out of a callback [uri].
  ///
  /// Throws [IntegrationException] when the service said `error=` instead,
  /// and when there is no code at all.
  static String authorizationCodeOf(Uri uri) {
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      if (error == 'access_denied') {
        throw const IntegrationException.cancelled(
          'Access was not granted, so nothing was connected.',
        );
      }
      throw IntegrationException(
        IntegrationFailure.serviceError,
        'The service refused the authorisation: $error',
      );
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const IntegrationException(
        IntegrationFailure.serviceError,
        'The service sent no authorisation code back.',
      );
    }
    return code;
  }

  static String _normalizePath(String path) {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    return trimmed.isEmpty ? '/' : trimmed;
  }
}

/// Non-file links, as the OAuth flows consume them.
///
/// [incomingDeepLinksProvider] publishes the latest link as an `AsyncValue`;
/// a flow needs a stream it can subscribe to *before* it opens anything, so
/// this provider republishes it. Reading it starts the subscription, which is
/// why the connect actions read it before they launch a browser.
final oauthDeepLinksProvider = Provider<Stream<Uri>>((ref) {
  final controller = StreamController<Uri>.broadcast();
  ref.listen<AsyncValue<Uri>>(incomingDeepLinksProvider, (previous, next) {
    final uri = next.value;
    if (uri == null || uri == previous?.value) return;
    if (!controller.isClosed) controller.add(uri);
  }, fireImmediately: true);
  ref.onDispose(controller.close);
  return controller.stream;
});

/// The OAuth flow the connect actions run.
final oauthFlowProvider = Provider.family<OAuthFlow, String>(
  (ref, callbackScheme) => OAuthFlow(
    callbackScheme: callbackScheme,
    deepLinks: ref.watch(oauthDeepLinksProvider),
  ),
);
