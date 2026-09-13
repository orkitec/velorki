import 'package:dio/dio.dart';

import '../../../../core/http/user_agent.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The dio Ride with GPS is talked to over.
final rwgpsDioProvider = Provider<Dio>((ref) {
  final dio = Dio(velorkiBaseOptions(rwgpsBaseOptions()));
  dio.interceptors.add(
    OAuthTokenInterceptor(
      tokens: ref.watch(rwgpsTokenSourceProvider),
      dio: () => dio,
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// The Ride with GPS API client.
final rwgpsClientProvider = Provider<RwgpsClient>(
  (ref) => RwgpsClient(dio: ref.watch(rwgpsDioProvider)),
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
    readUser: (token) async {
      // The token is not in secure storage yet, so this one call carries it
      // by hand instead of going through the interceptor.
      final dio = Dio(velorkiBaseOptions(rwgpsBaseOptions()))
        ..options.headers['Authorization'] = 'Bearer $token';
      try {
        return await RwgpsClient(dio: dio).currentUser();
      } finally {
        dio.close();
      }
    },
  );
});
