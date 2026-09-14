import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

const start = LatLng(48.137213, 11.575612);
const mid = LatLng(48.142011, 11.590447);
const end = LatLng(48.136002, 11.617833);

void main() {
  final backend = BRouterHttpBackend('https://brouter.example.org');
  tearDownAll(backend.close);

  group('point to point', () {
    test('lonlats are longitude first, pipe separated, in order', () {
      final uri = backend.buildUri(
        const RouteQuery(points: [start, mid, end], profile: 'fastbike'),
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'brouter.example.org');
      expect(uri.path, '/brouter');
      expect(
        uri.queryParameters['lonlats'],
        '11.575612,48.137213|11.590447,48.142011|11.617833,48.136002',
      );
      expect(uri.queryParameters['profile'], 'fastbike');
      expect(uri.queryParameters['alternativeidx'], '0');
      expect(uri.queryParameters['format'], 'geojson');
      expect(uri.queryParameters['timode'], '2', reason: 'voice hints');
      expect(uri.queryParameters.containsKey('engineMode'), isFalse);
      expect(uri.queryParameters.containsKey('allowSamewayback'), isFalse);
    });

    test('alternatives and trailing zeros', () {
      final uri = backend.buildUri(
        const RouteQuery(
          points: [LatLng(48.0, 11.5), LatLng(48.25, 11.0)],
          alternativeIdx: 3,
        ),
      );
      expect(uri.queryParameters['alternativeidx'], '3');
      expect(uri.queryParameters['lonlats'], '11.5,48|11,48.25');
    });

    test('allowSameWayBack false is sent as allowSamewayback=0', () {
      final uri = backend.buildUri(
        const RouteQuery(points: [start, end], allowSameWayBack: false),
      );
      expect(uri.queryParameters['allowSamewayback'], '0');
    });

    test('nogos are lon,lat,radius with an optional weight', () {
      final uri = backend.buildUri(
        RouteQuery(
          points: const [start, end],
          nogos: const [
            NoGo(center: LatLng(48.14, 11.6), radiusM: 250),
            NoGo(center: LatLng(48.15, 11.61), radiusM: 100, weight: 4.5),
          ],
        ),
      );
      expect(
        uri.queryParameters['nogos'],
        '11.6,48.14,250|11.61,48.15,100,4.5',
      );
    });

    test('rejects fewer than two points', () {
      expect(
        () => backend.buildUri(const RouteQuery(points: [start])),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.invalid,
          ),
        ),
      );
      expect(
        () => backend.buildUri(const RouteQuery(points: [])),
        throwsA(isA<RoutingException>()),
      );
    });
  });

  group('round trip', () {
    test('sends engineMode=4, a metre radius and a start direction', () {
      final uri = backend.buildUri(
        const RouteQuery(
          points: [start],
          profile: 'trekking',
          roundTrip: true,
          roundTripDistanceM: 7800,
          roundTripDirectionDeg: 135,
        ),
      );
      expect(uri.queryParameters['engineMode'], '4');
      expect(uri.queryParameters['lonlats'], '11.575612,48.137213');
      expect(uri.queryParameters['roundTripDistance'], '7800');
      expect(uri.queryParameters['direction'], '135');
    });

    test('only the start point is sent even with extra points', () {
      final uri = backend.buildUri(
        const RouteQuery(points: [start, mid], roundTrip: true),
      );
      expect(uri.queryParameters['lonlats'], '11.575612,48.137213');
      expect(uri.queryParameters.containsKey('roundTripDistance'), isFalse);
      expect(uri.queryParameters.containsKey('direction'), isFalse);
    });

    test('the direction is normalised into 0..359', () {
      final uri = backend.buildUri(
        const RouteQuery(
          points: [start],
          roundTrip: true,
          roundTripDirectionDeg: -45,
        ),
      );
      expect(uri.queryParameters['direction'], '315');
    });

    test('roundTripPoints is sent when the backend configures it', () {
      final b = BRouterHttpBackend(
        'https://brouter.example.org',
        roundTripPoints: 7,
      );
      final uri = b.buildUri(
        const RouteQuery(points: [start], roundTrip: true),
      );
      expect(uri.queryParameters['roundTripPoints'], '7');
      b.close();
    });
  });

  group('base url', () {
    test('a trailing slash is tolerated', () {
      final b = BRouterHttpBackend('https://brouter.example.org/');
      expect(
        b.buildUri(const RouteQuery(points: [start, end])).path,
        '/brouter',
      );
      b.close();
    });

    test('a path prefix is kept', () {
      final b = BRouterHttpBackend('https://example.org/routing/');
      expect(
        b.buildUri(const RouteQuery(points: [start, end])).path,
        '/routing/brouter',
      );
      b.close();
    });

    test('a port is kept', () {
      final b = BRouterHttpBackend('http://127.0.0.1:17777');
      final uri = b.buildUri(const RouteQuery(points: [start, end]));
      expect(uri.port, 17777);
      expect(uri.scheme, 'http');
      b.close();
    });
  });
}
