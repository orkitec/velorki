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
        'timode': '2',
      },
    );
  });

  test('turn instructions are always asked for', () {
    // Both backends want the `voicehints` table, so `timode` is not optional.
    expect(
      buildQueryParams(const RouteQuery(points: [start, end]))['timode'],
      '2',
    );
    expect(
      buildQueryParams(
        const RouteQuery(points: [start], roundTrip: true),
      )['timode'],
      '2',
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

  test('a round trip that may come back the same way says so', () {
    // The engine's own default is 0, so leaving it unsaid made the sheet's
    // "different way back" switch do nothing at all on the device.
    final params = buildQueryParams(
      const RouteQuery(
        points: [start],
        roundTrip: true,
        roundTripDistanceM: 4200,
      ),
    );
    expect(params['allowSamewayback'], '1');
  });

  test('a plain route never says allowSamewayback=1', () {
    // There it means "append the mirrored waypoints", which would double the
    // route behind the caller's back.
    final params = buildQueryParams(const RouteQuery(points: [start, end]));
    expect(params.containsKey('allowSamewayback'), isFalse);
  });

  test('profile parameters are sent as profile:<name>', () {
    final params = buildQueryParams(
      const RouteQuery(
        points: [start, end],
        profileParams: {'allow_ferries': '0', 'maxSpeed': '25'},
      ),
    );
    expect(params['profile:allow_ferries'], '0');
    expect(params['profile:maxSpeed'], '25');
    expect(
      buildQueryString(
        const RouteQuery(
          points: [start, end],
          profileParams: {'allow_ferries': '0'},
        ),
      ),
      contains('profile%3Aallow_ferries=0'),
    );
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
