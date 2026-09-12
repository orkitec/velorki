import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../domain/connected_account.dart';
import '../domain/integration_exception.dart';
import 'connected_accounts_repository.dart';

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

  /// The bearer token to put on the next request.
  Future<String> accessToken({bool forceRefresh = false}) async =>
      (await account(forceRefresh: forceRefresh)).accessToken;

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

/// Puts the bearer token on every request and renews it when it expires.
///
/// A 401 that still gets through — a token revoked in the service's own
/// settings, a clock far enough off that the leeway did not help — triggers
/// one forced refresh and one retry. Multipart bodies are not retried: the
/// stream has already been consumed, and an upload is cheap to repeat by hand.
class OAuthTokenInterceptor extends Interceptor {
  /// Creates the interceptor.
  ///
  /// [dio] supplies the client used for the single retry; it is a callback so
  /// the interceptor can be attached to the very client it retries on.
  OAuthTokenInterceptor({required this.tokens, required this.dio});

  /// Where the access token comes from.
  final OAuthTokenSource tokens;

  /// The client used for the single retry after a 401.
  final Dio Function() dio;

  /// Marks a request that has already been retried once.
  static const String retriedKey = 'velorki.retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      options.headers['Authorization'] = 'Bearer ${await tokens.accessToken()}';
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
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final retryable =
        err.response?.statusCode == 401 &&
        options.extra[retriedKey] != true &&
        options.data is! FormData;
    if (!retryable) {
      handler.next(err);
      return;
    }
    try {
      final token = await tokens.accessToken(forceRefresh: true);
      options
        ..headers['Authorization'] = 'Bearer $token'
        ..extra[retriedKey] = true;
      handler.resolve(await dio().fetch<dynamic>(options));
    } on Object catch (e) {
      _log.info('retry after 401 failed', e);
      handler.next(err);
    }
  }
}
