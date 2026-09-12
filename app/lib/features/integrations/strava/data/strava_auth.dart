import '../../common/data/oauth_flow.dart';

/// The authorisation URLs of Strava's OAuth, and nothing else.
///
/// Two of them, because Strava has two ways in:
///
/// * **App to app.** `strava://oauth/mobile/authorize` opens the installed
///   Strava app, which authorises without the rider typing a password. Strava
///   documents this for iOS; the app checks `canLaunchUrl` first and the
///   answer is `false` whenever Strava is not installed. The Strava app sends
///   the rider back with an ordinary `velorki://oauth/strava?code=…` link,
///   which is why [OAuthFlow] also listens on the deep-link stream.
/// * **The web page.** `https://www.strava.com/oauth/mobile/authorize` is the
///   mobile-shaped authorisation page. On Android this very URL is what Strava
///   documents, because the installed Strava app registers an intent filter for
///   it and takes it over; without the app it opens in a Custom Tab.
///
/// <https://developers.strava.com/docs/authentication/>
abstract final class StravaAuth {
  /// Everything Velorki needs: read the athlete, write activities, read the
  /// athlete's own activities and routes.
  static const String defaultScope = 'read,activity:write,activity:read';

  /// The path of the redirect, below the app's custom scheme.
  static const String redirectPath = 'oauth/strava';

  /// Strava's mobile authorisation page.
  static const String webAuthorizeBase =
      'https://www.strava.com/oauth/mobile/authorize';

  /// The app-to-app URL of the installed Strava app.
  static const String appAuthorizeBase = 'strava://oauth/mobile/authorize';

  /// The redirect URI both flows are told to come back to.
  ///
  /// Must match the relay's `OAUTH_REDIRECT_ALLOWLIST` exactly, and its host
  /// (`oauth`) must be the Authorization Callback Domain of the Strava API
  /// application.
  static Uri redirectUri(String scheme) => Uri.parse('$scheme://$redirectPath');

  /// The authorisation URL for the web session.
  static Uri webAuthorizeUrl({
    required String clientId,
    required Uri redirectUri,
    String scope = defaultScope,
    String approvalPrompt = 'auto',
    String? state,
  }) => _authorizeUrl(
    base: webAuthorizeBase,
    clientId: clientId,
    redirectUri: redirectUri,
    scope: scope,
    approvalPrompt: approvalPrompt,
    state: state,
  );

  /// The authorisation URL handed to the installed Strava app.
  static Uri appAuthorizeUrl({
    required String clientId,
    required Uri redirectUri,
    String scope = defaultScope,
    String approvalPrompt = 'auto',
    String? state,
  }) => _authorizeUrl(
    base: appAuthorizeBase,
    clientId: clientId,
    redirectUri: redirectUri,
    scope: scope,
    approvalPrompt: approvalPrompt,
    state: state,
  );

  static Uri _authorizeUrl({
    required String base,
    required String clientId,
    required Uri redirectUri,
    required String scope,
    required String approvalPrompt,
    String? state,
  }) => Uri.parse(base).replace(
    queryParameters: <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri.toString(),
      'response_type': 'code',
      'approval_prompt': approvalPrompt,
      'scope': scope,
      'state': ?state,
    },
  );
}
