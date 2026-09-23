import 'package:dio/dio.dart';

import '../../../../core/http/user_agent.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_api/velorki_api.dart' show RelayClient;

import '../../../../app/app_config.dart';
import '../../common/data/connected_accounts_repository.dart';
import '../../common/data/oauth_flow.dart';
import '../../common/data/oauth_token_source.dart';
import '../../common/data/relay_client_provider.dart';
import '../../common/domain/connected_account.dart';
import 'rwgps_client.dart';
import 'rwgps_connector.dart';

/// Base options shared by the Ride with GPS clients.
BaseOptions rwgpsBaseOptions() => BaseOptions(
  connectTimeout: const Duration(seconds: 20),
  receiveTimeout: const Duration(seconds: 60),
  sendTimeout: const Duration(minutes: 2),
  headers: <String, String>{'Accept': 'application/json'},
);

/// Ride with GPS tokens do not expire and there is nothing to refresh with,
/// so this source only ever reads what is stored.
final rwgpsTokenSourceProvider = Provider<OAuthTokenSource>(
  (ref) => OAuthTokenSource(
    service: IntegrationService.rwgps,
    repository: ref.watch(connectedAccountsRepositoryProvider),
    refresher: (expiring) async => expiring,
  ),
);

/// The dio Ride with GPS is talked to over, through the relay's pass-through.
final rwgpsDioProvider = Provider<Dio>((ref) {
  final relay = ref.watch(relayClientProvider);
  final dio = Dio(velorkiBaseOptions(rwgpsBaseOptions()))
    // Empty in a build without a relay, where Ride with GPS is hidden anyway.
    ..options.baseUrl =
        relay?.proxyBase(IntegrationService.rwgps.id).toString() ?? '';
  dio.interceptors.add(
    OAuthTokenInterceptor(
      tokens: ref.watch(rwgpsTokenSourceProvider),
      dio: () => dio,
      relayHeaders: () => relay?.proxyHeaders ?? const <String, String>{},
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// The Ride with GPS API client.
final rwgpsClientProvider = Provider<RwgpsClient>(
  (ref) => RwgpsClient(dio: ref.watch(rwgpsDioProvider)),
);

/// Builds the throwaway dio the connector's one bare-token call is made over.
typedef RwgpsBareDioFactory = Dio Function();

/// The production [RwgpsBareDioFactory]: a fresh client with the app's base
/// options and no interceptor, since there is no stored token yet.
Dio buildRwgpsBareDio() => Dio(velorkiBaseOptions(rwgpsBaseOptions()));

/// How the connector builds that one client.
///
/// Behind a provider because the call goes out to the relay, which a test
/// has no way to answer; the default is the real factory.
final rwgpsBareDioProvider = Provider<RwgpsBareDioFactory>(
  (ref) => buildRwgpsBareDio,
);

/// Whether this build can connect Ride with GPS at all.
final rwgpsConfiguredProvider = Provider<bool>((ref) {
  final config = ref.watch(effectiveConfigProvider);
  return config.hasApi && config.rwgpsClientId.isNotEmpty;
});

/// The Ride with GPS connect flow, or `null` when this build has none.
final rwgpsConnectorProvider = Provider<RwgpsConnector?>((ref) {
  final config = ref.watch(effectiveConfigProvider);
  final relay = ref.watch(relayClientProvider);
  if (relay == null || config.rwgpsClientId.isEmpty) return null;
  return RwgpsConnector(
    flow: ref.watch(oauthFlowProvider(config.oauthScheme)),
    relayClient: relay,
    clientId: config.rwgpsClientId,
    callbackScheme: config.oauthScheme,
    // The interceptor puts the account's token on, as on any other call.
    revokeAt: (account) => ref.read(rwgpsClientProvider).revoke(),
    readUser: (token) async {
      // The token is not in secure storage yet, so this one call carries it
      // by hand instead of going through the interceptor; it still goes
      // through the relay, like every other.
      final dio = ref.read(rwgpsBareDioProvider)()
        ..options.baseUrl = relay
            .proxyBase(IntegrationService.rwgps.id)
            .toString()
        ..options.headers.addAll(relay.proxyHeaders)
        ..options.headers[RelayClient.tokenHeader] = token;
      try {
        return await RwgpsClient(dio: dio).currentUser();
      } finally {
        dio.close();
      }
    },
  );
});
