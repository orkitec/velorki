// The parameter map both backends build. The URL side of it is asserted in
// url_test.dart; here it is the map itself and the query string the on-device
// engine receives.

import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

const start = LatLng(48.137213, 11.575612);
const end = LatLng(48.136002, 11.617833);

void main() {
  test('the HTTP backend builds its URL from exactly these parameters', () {
    const q = RouteQuery(points: [start, end], profile: 'gravel');
    final backend = BRouterHttpBackend('https://brouter.example.org');
    addTearDown(backend.close);
    expect(backend.buildUri(q).queryParameters, buildQueryParams(q));
  });

  test('point to point', () {
    expect(
      buildQueryParams(const RouteQuery(points: [start, end])),
      <String, String>{
        'lonlats': '11.575612,48.137213|11.617833,48.136002',
        'profile': 'trekking',
        'alternativeidx': '0',
        'format': 'geojson',
      },
    );
  });

  test('round trips, nogos and same-way-back', () {
    final params = buildQueryParams(
      const RouteQuery(
        points: [start],
        roundTrip: true,
        roundTripDistanceM: 4200.6,
        roundTripDirectionDeg: -90,
        allowSameWayBack: false,
        nogos: [
          NoGo(center: end, radiusM: 250),
          NoGo(center: end, radiusM: 250, weight: 3.5),
        ],
      ),
      roundTripPoints: 7,
    );
    expect(params['engineMode'], '4');
    expect(params['roundTripDistance'], '4201');
    expect(params['direction'], '270');
    expect(params['roundTripPoints'], '7');
    expect(params['allowSamewayback'], '0');
    expect(
      params['nogos'],
      '11.617833,48.136002,250|11.617833,48.136002,250,3.5',
    );
    expect(params['lonlats'], '11.575612,48.137213');
  });

  test('rejects a query that cannot become a request', () {
    expect(
      () => buildQueryParams(const RouteQuery(points: [])),
      throwsA(
        isA<RoutingException>().having(
          (e) => e.kind,
          'kind',
          RoutingErrorKind.invalid,
        ),
      ),
    );
    expect(
      () => buildQueryParams(const RouteQuery(points: [start])),
      throwsA(isA<RoutingException>()),
    );
  });

  test('the query string is URL encoded for the engine', () {
    final query = buildQueryString(const RouteQuery(points: [start, end]));
    expect(query, startsWith('lonlats='));
    expect(query, contains('%7C'), reason: 'the waypoint separator');
    expect(query, contains('profile=trekking'));
    // What the engine parses out of it is the map again.
    expect(
      Uri.splitQueryString(query),
      buildQueryParams(const RouteQuery(points: [start, end])),
    );
  });

  test('coordinates keep six decimals and lose trailing zeros', () {
    expect(formatCoord(11.5), '11.5');
    expect(formatCoord(48.0), '48');
    expect(formatCoord(-16.9200001), '-16.92');
    expect(formatCoord(-16.1234567), '-16.123457');
  });

  test('BRouter error texts are classified the same on both paths', () {
    expect(
      classifyBRouterError('no track found at pass=0'),
      RoutingErrorKind.noRoute,
    );
    expect(
      classifyBRouterError('target island detected for section 0'),
      RoutingErrorKind.noRoute,
    );
    expect(
      classifyBRouterError('operation killed by thread-priority-watchdog'),
      RoutingErrorKind.noRoute,
    );
    expect(
      classifyBRouterError('unknown profile nonsense'),
      RoutingErrorKind.invalid,
    );
  });
}
