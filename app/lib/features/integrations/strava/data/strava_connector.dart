import 'package:logging/logging.dart';
import 'package:velorki_api/velorki_api.dart' as relay;

import '../../common/data/integration_connector.dart';
import '../../common/data/oauth_flow.dart';
import '../../common/data/relay_client_provider.dart';
import '../../common/domain/connected_account.dart';
import 'strava_auth.dart';
import 'strava_client.dart';

final Logger _log = Logger('StravaConnector');

/// Connects and disconnects the Strava account.
class StravaConnector implements IntegrationConnector {
  /// Creates a connector.
  ///
  /// [preferAppToApp] decides whether the installed Strava app is offered the
  /// authorisation first; it is `true` on iOS, where Strava documents the
  /// `strava://` scheme, and `false` on Android, where the Strava app takes
  /// over the https URL by itself.
  StravaConnector({
    required this.flow,
    required this.relayClient,
    required this.clientId,
    required this.callbackScheme,
    required this.deauthorize,
    this.preferAppToApp = false,
  });

  /// The OAuth plumbing.
  final OAuthFlow flow;

  /// The relay that holds Strava's client secret.
  final relay.RelayClient relayClient;

  /// `VELORKI_STRAVA_CLIENT_ID`.
  final String clientId;

  /// The app's custom scheme, `velorki`.
  final String callbackScheme;

  /// Whether to try the installed Strava app first.
  final bool preferAppToApp;

  /// Revokes the token at Strava; injected so a disconnect can be tested
  /// without a client.
  final Future<void> Function(ConnectedAccount account) deauthorize;

  @override
  IntegrationService get service => IntegrationService.strava;

  @override
  Future<ConnectedAccount> connect() async {
    final redirectUri = StravaAuth.redirectUri(callbackScheme);
    final callback = await flow.authorize(
      webAuthorizeUrl: StravaAuth.webAuthorizeUrl(
        clientId: clientId,
        redirectUri: redirectUri,
      ),
      redirectUri: redirectUri,
      appAuthorizeUrl: preferAppToApp
          ? StravaAuth.appAuthorizeUrl(
              clientId: clientId,
              redirectUri: redirectUri,
            )
          : null,
    );

    final relay.StravaTokens tokens;
    try {
      tokens = await relayClient.exchangeStravaCode(
        code: callback.code,
        redirectUri: redirectUri.toString(),
      );
    } on relay.RelayException catch (e) {
      throw integrationExceptionFor(e);
    }

    final athlete = tokens.athlete;
    _log.info('connected Strava athlete ${athlete?['id']}');
    return ConnectedAccount(
      service: IntegrationService.strava,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAtUtc,
      athleteId: athlete?['id'] == null ? null : '${athlete!['id']}',
      athleteName: athleteNameOf(athlete),
      scopes: callback.scopes,
    );
  }

  @override
  Future<void> revoke(ConnectedAccount account) async {
    try {
      await deauthorize(account);
    } on Object catch (e) {
      // Strava being unreachable must not keep the token on the phone.
      _log.info('deauthorize failed; disconnecting locally anyway', e);
    }
  }

  /// `"Firstname Lastname"` out of Strava's athlete object, or `null`.
  static String? athleteNameOf(Map<String, Object?>? athlete) {
    if (athlete == null) return null;
    final parts = <String>[
      if (athlete['firstname'] is String) athlete['firstname']! as String,
      if (athlete['lastname'] is String) athlete['lastname']! as String,
    ].where((part) => part.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');
    final username = athlete['username'];
    return username is String && username.isNotEmpty ? username : null;
  }
}

/// Turns a relay [relay.StravaTokens] refresh into an updated account.
///
/// Strava rotates the refresh token on every exchange, so the whole set is
/// replaced, never merged.
ConnectedAccount applyStravaRefresh(
  ConnectedAccount account,
  relay.StravaTokens tokens,
) => ConnectedAccount(
  service: IntegrationService.strava,
  accessToken: tokens.accessToken,
  refreshToken: tokens.refreshToken,
  expiresAt: tokens.expiresAtUtc,
  athleteId: account.athleteId,
  athleteName: account.athleteName,
  scopes: account.scopes,
);

/// A [TokenRefresher] over the relay's `POST /oauth/strava/refresh`.
Future<ConnectedAccount> refreshStravaThroughRelay(
  ConnectedAccount expiring, {
  required relay.RelayClient relayClient,
}) async {
  final refreshToken = expiring.refreshToken;
  if (refreshToken == null) return expiring;
  try {
    return applyStravaRefresh(
      expiring,
      await relayClient.refreshStrava(refreshToken: refreshToken),
    );
  } on relay.RelayException catch (e) {
    throw integrationExceptionFor(e);
  }
}

/// Revokes [account] at Strava with a one-off [StravaClient].
Future<void> deauthorizeWith(StravaClient client, ConnectedAccount account) =>
    client.deauthorize(accessToken: account.accessToken);
