import 'package:logging/logging.dart';
import 'package:velorki_api/velorki_api.dart' as relay;

import '../../common/data/integration_connector.dart';
import '../../common/data/oauth_flow.dart';
import '../../common/data/relay_client_provider.dart';
import '../../common/domain/connected_account.dart';
import '../domain/rwgps_models.dart';
import 'rwgps_auth.dart';

final Logger _log = Logger('RwgpsConnector');

/// Connects and disconnects the Ride with GPS account.
class RwgpsConnector implements IntegrationConnector {
  /// Creates a connector.
  ///
  /// [readUser] fetches `GET /users/current.json` with the brand-new token so
  /// the settings tile can show a name; it is injected because the client it
  /// needs can only be built once the token exists.
  RwgpsConnector({
    required this.flow,
    required this.relayClient,
    required this.clientId,
    required this.callbackScheme,
    required this.readUser,
  });

  /// The OAuth plumbing.
  final OAuthFlow flow;

  /// The relay that holds the Ride with GPS client secret.
  final relay.RelayClient relayClient;

  /// `VELORKI_RWGPS_CLIENT_ID`.
  final String clientId;

  /// The app's custom scheme, `velorki`.
  final String callbackScheme;

  /// Reads the connected user with [accessToken].
  final Future<RwgpsUser?> Function(String accessToken) readUser;

  @override
  IntegrationService get service => IntegrationService.rwgps;

  @override
  Future<ConnectedAccount> connect() async {
    final redirectUri = RwgpsAuth.redirectUri(callbackScheme);
    final callback = await flow.authorize(
      webAuthorizeUrl: RwgpsAuth.authorizeUrl(
        clientId: clientId,
        redirectUri: redirectUri,
      ),
      redirectUri: redirectUri,
    );

    final relay.RwgpsTokens tokens;
    try {
      tokens = await relayClient.exchangeRwgpsCode(
        code: callback.code,
        redirectUri: redirectUri.toString(),
      );
    } on relay.RelayException catch (e) {
      throw integrationExceptionFor(e);
    }

    // Best effort: a name makes the settings tile useful, but a connection
    // without one still works.
    RwgpsUser? user;
    try {
      user = await readUser(tokens.accessToken);
    } on Object catch (e) {
      _log.info('could not read the Ride with GPS user', e);
    }

    return ConnectedAccount(
      service: IntegrationService.rwgps,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAtUtc,
      athleteId: user?.id,
      athleteName: user?.name,
      scopes: callback.scopes,
    );
  }

  /// Nothing to revoke from the app: `POST /oauth/revoke.json` needs the
  /// client secret, which lives in the relay, and the relay has no revoke
  /// endpoint in v1. Disconnecting deletes the token from the phone; the rider
  /// can also remove the authorisation on ridewithgps.com.
  @override
  Future<void> revoke(ConnectedAccount account) async {}
}
