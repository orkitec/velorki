import 'route_query.dart';
import 'routing_exception.dart';

/// Builds BRouter's request parameters for [q].
///
/// The one place the wire format lives: [BRouterHttpBackend] turns the map
/// into the query string of its `/brouter` URL, and `LocalRoutingBackend`
/// hands the same map to the ported engine, whose `RoutingParamCollector`
/// reads exactly the same names. Sharing this is what makes an on-device
/// route identical to a server route.
///
/// See the README for what each parameter really means in BRouter 1.7.x;
/// [roundTripPoints] is the backend-level setting (`null` leaves the server
/// default of 5).
///
/// Throws [RoutingException] with [RoutingErrorKind.invalid] when the query
/// cannot produce a request at all.
Map<String, String> buildQueryParams(RouteQuery q, {int? roundTripPoints}) {
  if (q.points.isEmpty) {
    throw const RoutingException(
      kind: RoutingErrorKind.invalid,
      message: 'a route query needs at least one point',
    );
  }
  if (!q.roundTrip && q.points.length < 2) {
    throw const RoutingException(
      kind: RoutingErrorKind.invalid,
      message: 'a point-to-point query needs at least two points',
    );
  }

  final lonlats = (q.roundTrip ? [q.points.first] : q.points)
      .map((p) => '${formatCoord(p.lon)},${formatCoord(p.lat)}')
      .join('|');

  final params = <String, String>{
    'lonlats': lonlats,
    'profile': q.profile,
    'alternativeidx': '${q.alternativeIdx}',
    'format': 'geojson',
  };

  if (q.roundTrip) {
    params['engineMode'] = '4';
    if (q.roundTripDistanceM != null) {
      params['roundTripDistance'] = '${q.roundTripDistanceM!.round()}';
    }
    if (q.roundTripDirectionDeg != null) {
      final dir = (q.roundTripDirectionDeg! % 360 + 360) % 360;
      params['direction'] = '${dir.round()}';
    }
    if (roundTripPoints != null) {
      params['roundTripPoints'] = '$roundTripPoints';
    }
  }
  if (!q.allowSameWayBack) {
    params['allowSamewayback'] = '0';
  }
  if (q.nogos.isNotEmpty) {
    params['nogos'] = q.nogos
        .map(
          (n) => n.weight == null
              ? '${formatCoord(n.center.lon)},${formatCoord(n.center.lat)},'
                    '${formatCoord(n.radiusM)}'
              : '${formatCoord(n.center.lon)},${formatCoord(n.center.lat)},'
                    '${formatCoord(n.radiusM)},${formatCoord(n.weight!)}',
        )
        .join('|');
  }

  return params;
}

/// [buildQueryParams] rendered as a URL-encoded query string.
///
/// This is what the ported engine's `BRouter.routeQuery` takes: it runs the
/// string through the same `URLDecoder`-equivalent the HTTP server would.
String buildQueryString(RouteQuery q, {int? roundTripPoints}) => Uri(
  queryParameters: buildQueryParams(q, roundTripPoints: roundTripPoints),
).query;

/// BRouter's coordinate resolution is 1e-6 degrees, so six decimals is exact;
/// trailing zeros are trimmed to keep the URL readable.
String formatCoord(double v) {
  var s = v.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// The error texts BRouter uses for "there is no route", as opposed to a
/// rejected request.
const List<String> brouterNoRouteMarkers = <String>[
  'no track found',
  'no route',
  'island',
  'not mapped',
  'unreachable',
  'no datafile',
  'no elevation',
  'too far',
  'operation killed',
];

/// Classifies one of BRouter's plain-text error messages.
///
/// The same texts come back from the HTTP server (as an HTTP 200 body) and
/// from the ported engine (as its `getErrorMessage()`), so both backends
/// report the same [RoutingErrorKind] for the same failure.
RoutingErrorKind classifyBRouterError(String text) {
  final lower = text.toLowerCase();
  for (final marker in brouterNoRouteMarkers) {
    if (lower.contains(marker)) return RoutingErrorKind.noRoute;
  }
  return RoutingErrorKind.invalid;
}
