import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

const query = RouteQuery(
  points: [LatLng(48.137213, 11.575612), LatLng(48.136002, 11.617833)],
);

String get fixture =>
    File('test/fixtures/route_trekking.geojson').readAsStringSync();

BRouterHttpBackend backendReturning(
  FutureOr<http.Response> Function(http.Request) handler,
) => BRouterHttpBackend(
  'https://brouter.example.org',
  client: MockClient((req) async => handler(req)),
);

void main() {
  group('happy path', () {
    test('a GeoJSON answer becomes a RouteResult', () async {
      late Uri seen;
      final backend = backendReturning((req) {
        seen = req.url;
        return http.Response(
          fixture,
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final result = await backend.route(query);
      expect(result.lengthM, 6000);
      expect(result.geometry, hasLength(11));
      expect(result.surfaceStats.busyShare, closeTo(0.15, 1e-12));
      expect(seen.path, '/brouter');
      expect(seen.queryParameters['format'], 'geojson');
    });
  });

  group('errors', () {
    test(
      'BRouter reports "no track found" with HTTP 200 and plain text',
      () async {
        final backend = backendReturning(
          (_) => http.Response('no track found at pass=0', 200),
        );
        await expectLater(
          backend.route(query),
          throwsA(
            isA<RoutingException>()
                .having((e) => e.kind, 'kind', RoutingErrorKind.noRoute)
                .having(
                  (e) => e.message,
                  'message',
                  contains('no track found'),
                ),
          ),
        );
      },
    );

    test('a target island is a noRoute too', () async {
      final backend = backendReturning(
        (_) => http.Response('target island detected for start-point', 200),
      );
      await expectLater(
        backend.route(query),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.noRoute,
          ),
        ),
      );
    });

    test('an unrecognised plain-text body is invalid', () async {
      final backend = backendReturning(
        (_) => http.Response('profile bikefoo.brf does not exist', 200),
      );
      await expectLater(
        backend.route(query),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.invalid,
          ),
        ),
      );
    });

    test('HTTP 500 is a network error', () async {
      final backend = backendReturning(
        (_) => http.Response('upstream exploded', 500),
      );
      await expectLater(
        backend.route(query),
        throwsA(
          isA<RoutingException>()
              .having((e) => e.kind, 'kind', RoutingErrorKind.network)
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('HTTP 400 is an invalid request', () async {
      final backend = backendReturning((_) => http.Response('bad params', 400));
      await expectLater(
        backend.route(query),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.invalid,
          ),
        ),
      );
    });

    test('a truncated JSON body is invalid', () async {
      final backend = backendReturning(
        (_) => http.Response('{"type": "FeatureColl', 200),
      );
      await expectLater(
        backend.route(query),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.invalid,
          ),
        ),
      );
    });

    test('JSON that is not a BRouter track is invalid', () async {
      final backend = backendReturning(
        (_) => http.Response(jsonEncode({'type': 'Feature'}), 200),
      );
      await expectLater(
        backend.route(query),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.invalid,
          ),
        ),
      );
    });

    test('a socket failure is a network error', () async {
      final backend = backendReturning(
        (_) => throw const SocketException('connection refused'),
      );
      await expectLater(
        backend.route(query),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.network,
          ),
        ),
      );
    });

    test('a slow server trips the client-side timeout', () async {
      final backend = backendReturning((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response(fixture, 200);
      });
      await expectLater(
        backend.route(
          query.copyWith(timeout: const Duration(milliseconds: 20)),
        ),
        throwsA(
          isA<RoutingException>()
              .having((e) => e.kind, 'kind', RoutingErrorKind.network)
              .having((e) => e.message, 'message', contains('did not answer')),
        ),
      );
    });
  });

  group('cancellation', () {
    test('a token cancelled up front short-circuits', () async {
      var called = false;
      final backend = backendReturning((_) {
        called = true;
        return http.Response(fixture, 200);
      });
      final cancel = CancelToken()..cancel('user changed the plan');
      await expectLater(
        backend.route(query, cancel: cancel),
        throwsA(
          isA<RoutingException>()
              .having((e) => e.kind, 'kind', RoutingErrorKind.cancelled)
              .having((e) => e.message, 'message', 'user changed the plan'),
        ),
      );
      expect(called, isFalse);
    });

    test('a token cancelled in flight aborts the wait', () async {
      final backend = backendReturning((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response(fixture, 200);
      });
      final cancel = CancelToken();
      final pending = backend.route(query, cancel: cancel);
      Timer(const Duration(milliseconds: 10), cancel.cancel);
      await expectLater(
        pending,
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.cancelled,
          ),
        ),
      );
      expect(cancel.isCancelled, isTrue);
      expect(cancel.reason, 'cancelled');
    });

    test('cancelling twice is a no-op', () {
      final cancel = CancelToken()
        ..cancel('first')
        ..cancel('second');
      expect(cancel.reason, 'first');
    });
  });

  test('parseResponse is usable without HTTP', () {
    final result = BRouterHttpBackend.parseResponse(200, fixture);
    expect(result.lengthM, 6000);
    expect(
      () => BRouterHttpBackend.parseResponse(200, '   '),
      throwsA(isA<RoutingException>()),
    );
  });
}
