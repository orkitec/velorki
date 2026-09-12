import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'models.dart';
import 'plan_events.dart';
import 'sse.dart';
import 'version.dart';

/// The client for the Velorki relay.
///
/// The relay exists so the OAuth client secrets of Strava and Ride with GPS,
/// and the LLM API key, never ship inside the open-source app. This class is
/// the only place in the app that talks to it.
///
/// ```dart
/// final client = RelayClient(
///   'https://relay.velorki.app',
///   clientId: 'android/1.4.0',
///   appUserId: revenueCatAppUserId,
/// );
/// try {
///   final tokens = await client.exchangeStravaCode(
///     code: code,
///     redirectUri: 'velorki://oauth/strava',
///   );
/// } on RelayException catch (e) {
///   log(e.error.message);
/// } finally {
///   client.close();
/// }
/// ```
///
/// Every method throws [RelayException] — and only [RelayException] — when a
/// call does not succeed, including for transport failures. Responses that
/// arrive but cannot be understood throw [RelayFormatException].
class RelayClient {
  /// Creates a client against [baseUrl].
  ///
  /// [baseUrl] may carry a path prefix and any number of trailing slashes;
  /// endpoint paths are joined onto it safely.
  ///
  /// [client] is the underlying HTTP client. Pass one to share a connection
  /// pool, or to inject a `package:http/testing.dart` `MockClient` in tests.
  /// A client created here is closed by [close]; an injected one is closed by
  /// [close] as well, so do not share one you still need afterwards.
  ///
  /// [clientId] becomes the `X-Velorki-Client` header and should read
  /// `<platform>/<version>`, e.g. `ios/1.4.0`. It defaults to
  /// `dart/<package version>`.
  ///
  /// [appUserId] is the RevenueCat app user id. Every relay endpoint is
  /// entitlement-gated, so when it is set it is sent as
  /// `Authorization: Bearer <appUserId>` on every request.
  RelayClient(
    String baseUrl, {
    http.Client? client,
    String? clientId,
    this.appUserId,
  }) : _base = _normalizeBase(baseUrl),
       _client = client ?? http.Client(),
       clientId = clientId ?? 'dart/$packageVersion';

  /// The value sent in the `X-Velorki-Client` header.
  final String clientId;

  /// The RevenueCat app user id sent as a bearer token, when set.
  final String? appUserId;

  final String _base;
  final http.Client _client;

  /// The header name carrying the client platform and version.
  static const String clientHeader = 'X-Velorki-Client';

  /// The header the AI endpoints require to be `1`.
  static const String consentHeader = 'X-AI-Consent';

  /// Strips trailing slashes so paths can be appended verbatim.
  static String _normalizeBase(String baseUrl) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  /// Builds the absolute [Uri] for a relay [path] such as `/share`.
  Uri uriFor(String path) =>
      Uri.parse('$_base${path.startsWith('/') ? path : '/$path'}');

  /// The headers every request carries.
  Map<String, String> _headers({
    bool json = true,
    String? overrideAppUserId,
    bool consent = false,
    String accept = 'application/json',
  }) {
    final user = overrideAppUserId ?? appUserId;
    return <String, String>{
      clientHeader: clientId,
      'Accept': accept,
      if (json) 'Content-Type': 'application/json; charset=utf-8',
      if (user != null) 'Authorization': 'Bearer $user',
      if (consent) consentHeader: '1',
    };
  }

  /* --------------------------------------------------------------- Strava */

  /// Exchanges an OAuth authorization [code] for Strava tokens.
  ///
  /// [redirectUri] must be one the relay allowlists; it is forwarded to Strava
  /// and therefore decides where a stolen code could be sent.
  Future<StravaTokens> exchangeStravaCode({
    required String code,
    required String redirectUri,
  }) async => StravaTokens.fromJson(
    await _postJson('/oauth/strava/token', <String, Object?>{
      'code': code,
      'redirect_uri': redirectUri,
    }),
  );

  /// Trades a Strava [refreshToken] for a fresh access token.
  ///
  /// Strava rotates refresh tokens, so store the whole returned token set.
  Future<StravaTokens> refreshStrava({required String refreshToken}) async =>
      StravaTokens.fromJson(
        await _postJson('/oauth/strava/refresh', <String, Object?>{
          'refresh_token': refreshToken,
        }),
      );

  /* --------------------------------------------------------- Ride with GPS */

  /// Exchanges an OAuth authorization [code] for Ride with GPS tokens.
  ///
  /// There is no refresh counterpart: Ride with GPS access tokens do not
  /// expire, and the relay answers `/oauth/rwgps/refresh` with `unavailable`.
  Future<RwgpsTokens> exchangeRwgpsCode({
    required String code,
    required String redirectUri,
  }) async => RwgpsTokens.fromJson(
    await _postJson('/oauth/rwgps/token', <String, Object?>{
      'code': code,
      'redirect_uri': redirectUri,
    }),
  );

  /* ---------------------------------------------------------------- share */

  /// Stores [gpx] on the relay and returns its public link.
  ///
  /// [name] is the title shown on the share page and the basis of the GPX
  /// download filename. [summary] carries the headline numbers rendered
  /// alongside the map; [kind] says whether this is a plan or a ride that
  /// happened. The relay caps the GPX at 2 MB.
  ///
  /// The stored record holds no account identifier: the returned
  /// [ShareLink.id] is the only capability guarding it.
  Future<ShareLink> createShare({
    required String name,
    required String gpx,
    required ShareSummary summary,
    ShareKind kind = ShareKind.route,
  }) async => ShareLink.fromJson(
    await _postJson('/share', <String, Object?>{
      'kind': kind.json,
      'name': name,
      'gpx': gpx,
      'summary': summary.toJson(),
    }),
  );

  /* -------------------------------------------------------------- ai/plan */

  /// Runs one `POST /ai/plan` request and streams its events.
  ///
  /// [step] is `plan` (the model proposes a route, answered with a single
  /// [RouteRequestEvent]) or `describe` (the model narrates an existing route,
  /// answered with a series of [TextEvent]s). `describe` requires
  /// [routeSummary].
  ///
  /// [prompt] is the rider's free text, at most 1000 characters. [locale] is a
  /// BCP47 tag and decides the language of the answer. [context] gives the
  /// model a rough start position — round the coordinates before sending.
  ///
  /// [appUserId] overrides the client-wide RevenueCat id for this call; one of
  /// the two must be set, because the endpoint is entitlement-gated. The
  /// `X-AI-Consent: 1` header is always sent: this method must only be called
  /// after the rider has consented to their text being sent to a third-party
  /// model.
  ///
  /// The returned stream is single-subscription and lazy — the request is only
  /// sent when it is listened to. Cancelling the subscription aborts the
  /// request, which stops the relay paying for tokens.
  ///
  /// A relay failure *before* the stream opens throws [RelayException]. A
  /// failure *after* it opened arrives as an [ErrorEvent] and the stream then
  /// ends normally; see [ErrorEvent] for why. Events whose name is not part of
  /// the contract are dropped.
  Stream<PlanEvent> planStream({
    required String step,
    required String prompt,
    String locale = 'en',
    PlanUnits units = PlanUnits.metric,
    PlanContext? context,
    RouteSummary? routeSummary,
    String? appUserId,
  }) async* {
    final body = <String, Object?>{
      'step': step,
      'locale': locale,
      'units': units.json,
      'prompt': prompt,
      if (context != null) 'context': context.toJson(),
      if (routeSummary != null) 'route_summary': routeSummary.toJson(),
    };

    final request = http.Request('POST', uriFor('/ai/plan'))
      ..headers.addAll(
        _headers(
          overrideAppUserId: appUserId,
          consent: true,
          accept: 'text/event-stream',
        ),
      )
      ..body = jsonEncode(body);

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on Object catch (e) {
      throw _transportException(e);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The failure came before the stream opened, so the body is a normal
      // uniform error document.
      final text = await response.stream.bytesToString();
      throw _httpException(response.statusCode, text, response.headers);
    }

    await for (final event in parseSse(response.stream)) {
      final planEvent = planEventFromSse(event);
      if (planEvent != null) yield planEvent;
    }
  }

  /* ------------------------------------------------------------- plumbing */

  /// POSTs [body] as JSON and returns the decoded response object.
  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client.post(
        uriFor(path),
        headers: _headers(),
        body: jsonEncode(body),
      );
    } on Object catch (e) {
      throw _transportException(e);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpException(
        response.statusCode,
        response.body,
        response.headers,
      );
    }
    return decodeJsonObject(response.body, what: 'response body');
  }

  /// Wraps anything the transport threw in a [RelayException].
  ///
  /// `SocketException` is deliberately not caught by type: importing
  /// `dart:io` would make this package unusable on the web, and an
  /// `http.ClientException` is not the only thing a platform client can throw.
  /// Whatever it is, the caller gets an `unavailable` error instead.
  static RelayException _transportException(Object cause) {
    if (cause is RelayException) return cause;
    final detail = cause is http.ClientException ? cause.message : '$cause';
    return RelayException(
      RelayError(
        code: RelayErrorCode.unavailable,
        message: 'Could not reach the Velorki relay: $detail',
      ),
    );
  }

  /// Maps a non-2xx response onto a [RelayException].
  ///
  /// Prefers the uniform error body. When the body is something else — an HTML
  /// error page from a proxy, an empty body, a JSON document of another shape
  /// — an error is synthesised from the status code so callers never see a
  /// parse failure where they expected a relay error.
  static RelayException _httpException(
    int status,
    String body,
    Map<String, String> headers,
  ) {
    RelayError? parsed;
    try {
      parsed = RelayError.fromBody(jsonDecode(body));
    } on Object {
      parsed = null;
    }

    final retryAfter =
        parsed?.retryAfterS ??
        int.tryParse(headers['retry-after'] ?? headers['Retry-After'] ?? '');

    final error = parsed == null
        ? RelayError(
            code: _codeForStatus(status),
            message: _messageForStatus(status, body),
            retryAfterS: retryAfter,
          )
        : RelayError(
            code: parsed.code,
            message: parsed.message,
            retryAfterS: retryAfter,
          );
    return RelayException(error, statusCode: status);
  }

  /// The error code the relay would have used for [status].
  static String _codeForStatus(int status) => switch (status) {
    400 => RelayErrorCode.invalidRequest,
    401 => RelayErrorCode.notEntitled,
    403 => RelayErrorCode.consentRequired,
    404 => RelayErrorCode.notFound,
    429 => RelayErrorCode.rateLimited,
    503 => RelayErrorCode.unavailable,
    _ =>
      status >= 500
          ? RelayErrorCode.upstreamError
          : RelayErrorCode.invalidRequest,
  };

  /// A short, safe message for a response that carried no usable error body.
  static String _messageForStatus(int status, String body) {
    final snippet = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (snippet.isEmpty) {
      return 'The Velorki relay answered $status with an empty body.';
    }
    // A proxy's HTML page is noise; keep a bounded excerpt for the log.
    final excerpt = snippet.length > 160
        ? '${snippet.substring(0, 160)}...'
        : snippet;
    return 'The Velorki relay answered $status: $excerpt';
  }

  /// Closes the underlying HTTP client. In-flight requests are aborted.
  void close() => _client.close();
}
