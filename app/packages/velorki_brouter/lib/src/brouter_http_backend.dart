import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'brouter_query.dart';
import 'route_query.dart';
import 'route_result.dart';
import 'routing_backend.dart';
import 'routing_exception.dart';

/// [RoutingBackend] talking to a BRouter HTTP server (`/brouter`).
///
/// Point it at a self-hosted BRouter — the public brouter.de instance is not
/// an acceptable app backend.
///
/// ## Parameters, as BRouter 1.7.8 really spells them
///
/// Verified against upstream `RoutingParamCollector.java`, `RouteServer.java`
/// and `RoutingEngine.java` (github.com/abrensch/brouter, master, 2026-09):
///
/// * `lonlats=lon,lat|lon,lat` — waypoints, longitude first.
/// * `profile`, `alternativeidx` (0..3), `format=geojson`.
/// * `engineMode=4` — the numeric constant `BROUTER_ENGINEMODE_ROUNDTRIP`.
///   There is no `engineMode=roundtrip` spelling.
/// * `roundTripDistance` — camelCase, an **integer number of metres**, and it
///   is the *radius* of the circle BRouter places its generated waypoints on,
///   not the length of the route. The server default is 1500. (The value is
///   handed straight to `CheapRuler.destination`, whose distance argument is
///   metres.) Kilometres would be off by a factor of 1000.
/// * `direction` — start bearing in degrees clockwise from north. Without it
///   BRouter picks a random direction (`Math.random()`), so always send one for
///   reproducible results. (`roundTripStartDirection` does not exist in 1.7.10;
///   verified against the jar's `RoutingParamCollector`.)
/// * `roundTripPoints` — 3..20 generated points, default 5.
/// * `allowSamewayback=0|1` — lower-case `w` and `b`.
/// * `nogos=lon,lat,radius[,weight]|...` — radius in metres.
/// * There is **no** `timeout` query parameter. The server's limit is the JVM
///   system property `maxRunningTime`, so [RouteQuery.timeout] is enforced
///   client-side here.
///
/// ## Errors
///
/// BRouter answers a failed route with HTTP 200 and a plain-text body such as
/// `no track found at pass=0` or `target island detected ...`, so the status
/// code alone tells you nothing; the body is sniffed for JSON.
class BRouterHttpBackend implements RoutingBackend {
  /// Creates a backend for the BRouter server at [baseUrl].
  ///
  /// [baseUrl] is the server root (`https://brouter.example.org`) with or
  /// without a trailing slash; the `/brouter` path is appended. Inject a
  /// [client] in tests; when you let the backend create its own, call [close].
  BRouterHttpBackend(
    String baseUrl, {
    http.Client? client,
    this.defaultTimeout = const Duration(seconds: 25),
    this.roundTripPoints,
  }) : _base = _normalizeBase(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri _base;
  final http.Client _client;
  final bool _ownsClient;

  /// Deadline used when a [RouteQuery] does not carry its own.
  final Duration defaultTimeout;

  /// How many waypoints BRouter should generate in round-trip mode (3..20).
  /// `null` leaves the server default of 5.
  final int? roundTripPoints;

  /// The server root this backend talks to.
  Uri get baseUri => _base;

  /// Builds the request URL for [q]. Public so it can be asserted in tests.
  ///
  /// The parameters come from the shared [buildQueryParams], which
  /// `LocalRoutingBackend` also uses — that is what makes an on-device route
  /// identical to a server route.
  Uri buildUri(RouteQuery q) => _base.replace(
    path: '${_base.path}/brouter',
    queryParameters: buildQueryParams(q, roundTripPoints: roundTripPoints),
  );

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    if (cancel != null && cancel.isCancelled) throw cancel.toException();
    final uri = buildUri(q);
    final timeout = q.timeout ?? defaultTimeout;

    http.Response response;
    try {
      var pending = _client.get(uri).timeout(timeout);
      if (cancel != null) {
        pending = Future.any<http.Response>([
          pending,
          cancel.whenCancelled.then((_) => throw cancel.toException()),
        ]);
      }
      response = await pending;
    } on RoutingException {
      rethrow;
    } on TimeoutException catch (e) {
      throw RoutingException(
        kind: RoutingErrorKind.network,
        message: 'BRouter did not answer within ${timeout.inSeconds} s',
        cause: e,
      );
    } catch (e) {
      throw RoutingException(
        kind: RoutingErrorKind.network,
        message: 'cannot reach BRouter at $uri: $e',
        cause: e,
      );
    }
    if (cancel != null && cancel.isCancelled) throw cancel.toException();

    return parseResponse(response.statusCode, response.body);
  }

  /// Turns a raw BRouter answer into a [RouteResult] or a [RoutingException].
  ///
  /// Exposed so tests (and the future on-device backend's server fallback)
  /// can exercise the error handling without HTTP.
  static RouteResult parseResponse(int statusCode, String body) {
    final text = body.trim();
    if (statusCode != 200) {
      throw RoutingException(
        kind: statusCode >= 500
            ? RoutingErrorKind.network
            : RoutingErrorKind.invalid,
        message: text.isEmpty ? 'HTTP $statusCode' : text,
        statusCode: statusCode,
      );
    }
    if (!text.startsWith('{')) {
      // BRouter reports routing failures as HTTP 200 with a plain-text body.
      throw RoutingException(
        kind: classifyBRouterError(text),
        message: text.isEmpty ? 'empty answer from BRouter' : text,
        statusCode: statusCode,
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw RoutingException(
        kind: RoutingErrorKind.invalid,
        message: 'BRouter answer is not JSON: ${e.message}',
        cause: e,
        statusCode: statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const RoutingException(
        kind: RoutingErrorKind.invalid,
        message: 'BRouter answer is not a JSON object',
      );
    }
    return RouteResult.fromGeoJson(decoded);
  }

  /// Closes the HTTP client, if this backend created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  static Uri _normalizeBase(String baseUrl) {
    final uri = Uri.parse(baseUrl.trim());
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path, query: '', fragment: '');
  }
}
