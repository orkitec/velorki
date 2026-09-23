import 'package:dio/dio.dart';

import '../../../../core/http/user_agent.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_config.dart';
import '../../common/data/connected_accounts_repository.dart';
import '../../common/data/oauth_flow.dart';
import '../../common/data/oauth_token_source.dart';
import '../../common/data/relay_client_provider.dart';
import '../../common/data/token_bucket.dart';
import '../../common/domain/connected_account.dart';
import 'strava_client.dart';
import 'strava_connector.dart';

/// Keeps the Strava access token fresh, 60 seconds before it expires.
final stravaTokenSourceProvider = Provider<OAuthTokenSource>(
  (ref) => OAuthTokenSource(
    service: IntegrationService.strava,
    repository: ref.watch(connectedAccountsRepositoryProvider),
    refresher: (expiring) =>
        refreshStravaThroughRelay(expiring, relayClient: requireRelay(ref)),
    onRefreshed: (account) =>
        ref.read(connectedAccountsProvider.notifier).publish(account),
  ),
);

/// The dio Strava is talked to over, through the relay's pass-through:
/// wrapped token, refresh and one retry.
final stravaDioProvider = Provider<Dio>((ref) {
  final relay = ref.watch(relayClientProvider);
  final dio = Dio(
    velorkiBaseOptions(
      BaseOptions(
        // Empty in a build without a relay, where Strava is hidden anyway.
        baseUrl:
            relay?.proxyBase(IntegrationService.strava.id).toString() ?? '',
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(minutes: 2),
        headers: <String, String>{'Accept': 'application/json'},
      ),
    ),
  );
  dio.interceptors.add(
    OAuthTokenInterceptor(
      tokens: ref.watch(stravaTokenSourceProvider),
      dio: () => dio,
      relayHeaders: () => relay?.proxyHeaders ?? const <String, String>{},
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// The Strava API client.
final stravaClientProvider = Provider<StravaClient>(
  (ref) => StravaClient(
    dio: ref.watch(stravaDioProvider),
    readBucket: ref.watch(stravaReadBucketProvider),
  ),
);

/// Whether this build can connect Strava at all.
///
/// Needs both a relay — the client secret lives there — and a client id.
final stravaConfiguredProvider = Provider<bool>((ref) {
  final config = ref.watch(effectiveConfigProvider);
  return config.hasApi && config.stravaClientId.isNotEmpty;
});

/// The Strava connect flow, or `null` when this build has no Strava.
final stravaConnectorProvider = Provider<StravaConnector?>((ref) {
  final config = ref.watch(effectiveConfigProvider);
  final relay = ref.watch(relayClientProvider);
  if (relay == null || config.stravaClientId.isEmpty) return null;
  return StravaConnector(
    flow: ref.watch(oauthFlowProvider(config.oauthScheme)),
    relayClient: relay,
    clientId: config.stravaClientId,
    callbackScheme: config.oauthScheme,
    // Strava documents the `strava://` scheme for iOS. On Android the
    // installed Strava app registers an intent filter for the https mobile
    // authorise URL and takes it over by itself, so the web flow is the
    // app-to-app flow there.
    preferAppToApp: defaultTargetPlatform == TargetPlatform.iOS,
    // The interceptor puts the account's token on, as on any other call.
    deauthorize: (account) => ref.read(stravaClientProvider).deauthorize(),
  );
});

/// The Strava athlete id of the connected account, or `null`.
final stravaAthleteIdProvider = Provider<String?>(
  (ref) =>
      ref.watch(connectedAccountProvider(IntegrationService.strava))?.athleteId,
);
