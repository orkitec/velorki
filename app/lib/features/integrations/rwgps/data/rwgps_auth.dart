/// The authorisation URL of Ride with GPS' OAuth.
///
/// One way in only: Ride with GPS has no app-to-app scheme and no PKCE, so the
/// authorisation page opens in the web session and the relay holds the client
/// secret for the exchange.
///
/// <https://ridewithgps.com/api/v1/doc/authentication>
abstract final class RwgpsAuth {
  /// The path of the redirect, below the app's custom scheme.
  static const String redirectPath = 'oauth/rwgps';

  /// The authorisation page.
  static const String authorizeBase = 'https://ridewithgps.com/oauth/authorize';

  /// The redirect URI. Must be one of the API client's configured redirect
  /// URIs and on the relay's `OAUTH_REDIRECT_ALLOWLIST`.
  static Uri redirectUri(String scheme) => Uri.parse('$scheme://$redirectPath');

  /// The authorisation URL for the web session.
  static Uri authorizeUrl({
    required String clientId,
    required Uri redirectUri,
    String? state,
  }) => Uri.parse(authorizeBase).replace(
    queryParameters: <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri.toString(),
      'response_type': 'code',
      'state': ?state,
    },
  );
}
