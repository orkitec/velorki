import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:velorki_api/velorki_api.dart' show RelayClient, RelayErrorCode;

import '../domain/connected_account.dart';
import '../domain/integration_exception.dart';
import 'connected_accounts_repository.dart';
import 'dio_errors.dart';

final Logger _log = Logger('OAuthTokenSource');

/// Buys a fresh account for one whose access token is about to expire.
///
/// Implemented against the relay: the client secret lives there, so the phone
/// can only ask, never sign the request itself.
typedef TokenRefresher = Future<ConnectedAccount> Function(
  ConnectedAccount expiring,
);

/// Keeps one service's access token usable.
///
/// Refreshes [refreshLeeway] *before* the token expires rather than after a
/// 401, because Strava's clock and the phone's need not agree and an upload
/// that fails halfway is expensive. Concurrent callers share one refresh: two
/// screens asking at the same time must not spend the refresh token twice,
/// since Strava rotates it and the loser would be left holding a dead one.
class OAuthTokenSource {
  /// Creates a source for [service].
  OAuthTokenSource({
    required this.service,
    required this.repository,
    required this.refresher,
    this.refreshLeeway = const Duration(seconds: 60),
    this.onRefreshed,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long before expiry the token is renewed.
  static const Duration defaultLeeway = Duration(seconds: 60);

  /// Which service this source speaks for.
  final IntegrationService service;

  /// How long before expiry a refresh is triggered.
  final Duration refreshLeeway;

  /// Where the account is read and written.
  final ConnectedAccountsRepository repository;

  /// How a fresh account is bought.
  final TokenRefresher refresher;

  /// Told about every refresh, so the UI can follow along.
  final void Function(ConnectedAccount account)? onRefreshed;

  final DateTime Function() _clock;

  Future<ConnectedAccount>? _inFlight;

  /// The stored account, refreshed when it is due.
  ///
  /// Throws [IntegrationException] with [IntegrationFailure.notConnected] when
  /// nothing is connected.
  Future<ConnectedAccount> account({bool forceRefresh = false}) async {
    final stored = await repository.read(service);
    if (stored == null) {
      throw IntegrationException(
        IntegrationFailure.notConnected,
        'No ${service.id} account is connected.',
      );
    }
    final due =
        forceRefresh ||
        stored.needsRefresh(leeway: refreshLeeway, now: _clock());
    if (!due) return stored;
    if (stored.refreshToken == null) {
      // Nothing to refresh with; let the service reject the token instead of
      // pretending here.
      return stored;
    }
    return _inFlight ??= _refresh(stored);
  }

  /// The wrapped token to put on the next request.
  Future<String> accessToken({bool forceRefresh = false}) async =>
      (await account(forceRefresh: forceRefresh)).accessToken;

  /// Stores [wrapped] as the account's access token.
  ///
  /// The relay re-wraps a token that arrived under a key it is retiring and
  /// sends the new form back with the answer; from then on the old form is
  /// on borrowed time, so it is replaced at once. A refresh that landed in
  /// between wins: the token is only swapped under the account it came with.
  Future<void> replaceAccessToken(
    String wrapped, {
    required String replacing,
  }) async {
    final stored = await repository.read(service);
    if (stored == null || stored.accessToken != replacing) return;
    final updated = stored.copyWith(accessToken: wrapped);
    await repository.save(updated);
    onRefreshed?.call(updated);
  }

  Future<ConnectedAccount> _refresh(ConnectedAccount expiring) async {
    try {
      _log.info('refreshing the ${service.id} access token');
      final refreshed = await refresher(expiring);
      await repository.save(refreshed);
      onRefreshed?.call(refreshed);
      return refreshed;
    } finally {
      _inFlight = null;
    }
  }
}

/// Puts the wrapped token and the relay's own headers on every request, and
/// renews the token when it expires.
///
/// Every request goes to the relay's pass-through, so it carries two
/// credentials: the relay's bearer, which says who is asking, and the wrapped
/// service token in `X-Velorki-Token`, which the relay opens and forwards. A
/// 401 in the service's own words that still gets through — a token revoked
/// in the service's settings, a clock far enough off that the leeway did not
/// help — triggers one forced refresh and one retry. A 401 in the relay's
/// words is Plus having lapsed, and nothing a refresh could mend. Multipart
/// bodies are not retried: the stream has already been consumed, and an
/// upload is cheap to repeat by hand.
class OAuthTokenInterceptor extends Interceptor {
  /// Creates the interceptor.
  ///
  /// [dio] supplies the client used for the single retry; it is a callback so
  /// the interceptor can be attached to the very client it retries on.
  /// [relayHeaders] are the relay's own, read per request because the relay
  /// client can be rebuilt under a running dio.
  OAuthTokenInterceptor({
    required this.tokens,
    required this.dio,
    required this.relayHeaders,
  });

  /// Where the wrapped token comes from.
  final OAuthTokenSource tokens;

  /// The client used for the single retry after a 401.
  final Dio Function() dio;

  /// The relay's client id and bearer, see [RelayClient.proxyHeaders].
  final Map<String, String> Function() relayHeaders;

  /// Marks a request that has already been retried once.
  static const String retriedKey = 'velorki.retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      options.headers
        ..addAll(relayHeaders())
        ..[RelayClient.tokenHeader] = await tokens.accessToken();
    } on IntegrationException catch (e, stack) {
      handler.reject(
        DioException(requestOptions: options, error: e, stackTrace: stack),
        true,
      );
      return;
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final fresh = response.headers.value(RelayClient.rewrappedHeader);
    final sent = response.requestOptions.headers[RelayClient.tokenHeader];
    if (fresh != null && fresh.isNotEmpty && sent is String) {
      try {
        await tokens.replaceAccessToken(fresh, replacing: sent);
      } on Object catch (e) {
        // The old form still works until the key is dropped; the next
        // answer brings the new one again.
        _log.info('could not store the re-wrapped token', e);
      }
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final retryable =
        err.response?.statusCode == 401 &&
        relayErrorOf(err.response?.data)?.code != RelayErrorCode.notEntitled &&
        options.extra[retriedKey] != true &&
        options.data is! FormData;
    if (!retryable) {
      handler.next(err);
      return;
    }
    try {
      final token = await tokens.accessToken(forceRefresh: true);
      options
        ..headers[RelayClient.tokenHeader] = token
        ..extra[retriedKey] = true;
      handler.resolve(await dio().fetch<dynamic>(options));
    } on Object catch (e) {
      _log.info('retry after 401 failed', e);
      handler.next(err);
    }
  }
}
