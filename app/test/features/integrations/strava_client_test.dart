import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/token_bucket.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/strava/data/strava_client.dart';
import 'package:velorki/features/integrations/strava/domain/strava_models.dart';

import 'support/fake_dio.dart';
import 'support/fakes.dart';

/// No waiting: the poll backoff is the behaviour under test, not the clock.
Future<void> _noSleep(Duration _) async {}

void main() {
  group('uploadActivity', () {
    test('posts the file as multipart with Strava\'s field names', () async {
      final adapter = FakeApiAdapter(
        (_) => FakeResponse.json(<String, Object?>{
          'id': 1234,
          'id_str': '1234',
          'external_id': 'velorki-ride-1',
          'error': null,
          'status': 'Your activity is still being processed.',
          'activity_id': null,
        }),
      );
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
      );

      final upload = await client.uploadActivity(
        bytes: utf8.encode('<gpx/>'),
        dataType: StravaDataType.gpx,
        name: 'Morning loop',
        description: 'felt good',
        externalId: 'velorki-ride-1',
        fileName: 'velorki-ride-1.gpx',
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      // Relative to the relay's pass-through, which forwards the same path.
      expect(
        '${request.uri}',
        'https://relay.test/proxy/strava/api/v3/uploads',
      );
      expect(multipartFileNames(request), <String>['file']);
      expect(multipartFields(request), <String, String>{
        'data_type': 'gpx',
        'name': 'Morning loop',
        'description': 'felt good',
        'sport_type': 'Ride',
        'external_id': 'velorki-ride-1',
      });
      expect(upload.id, '1234');
      expect(upload.pending, isTrue);
    });
  });

  group('uploadAndWait', () {
    test('polls until Strava reports an activity', () async {
      var polls = 0;
      final adapter = FakeApiAdapter((options) {
        if (options.method == 'POST') {
          return FakeResponse.json(<String, Object?>{
            'id_str': '99',
            'status': 'Your activity is still being processed.',
          });
        }
        polls++;
        return FakeResponse.json(<String, Object?>{
          'id_str': '99',
          'status': polls < 3 ? 'processing' : 'Your activity is ready.',
          'activity_id': polls < 3 ? null : 5555,
        });
      });
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
      );

      final progress = <String?>[];
      final upload = await client.uploadAndWait(
        bytes: utf8.encode('<gpx/>'),
        dataType: StravaDataType.gpx,
        name: 'Morning loop',
        onProgress: (u) => progress.add(u.status),
      );

      expect(polls, 3);
      expect(upload.activityId, '5555');
      expect(upload.succeeded, isTrue);
      expect(upload.activityUrl, 'https://www.strava.com/activities/5555');
      expect(progress, hasLength(4));
      expect(adapter.uris.last.path, '/proxy/strava/api/v3/uploads/99');
    });

    test(
      'a non-empty error field ends the poll with a clear message',
      () async {
        final adapter = FakeApiAdapter((options) {
          if (options.method == 'POST') {
            return FakeResponse.json(<String, Object?>{'id_str': '7'});
          }
          return FakeResponse.json(<String, Object?>{
            'id_str': '7',
            'error': 'Your activity is a duplicate of 12345.',
            'status': 'There was an error processing your activity.',
          });
        });
        final client = StravaClient(
          dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
          sleep: _noSleep,
        );

        final e = await integrationFailure(
          () => client.uploadAndWait(
            bytes: utf8.encode('<gpx/>'),
            dataType: StravaDataType.gpx,
            name: 'Morning loop',
          ),
        );
        expect(e.failure, IntegrationFailure.rejected);
        expect(e.message, contains('duplicate'));
      },
    );

    test(
      'an upload that never finishes is reported, not awaited forever',
      () async {
        final adapter = FakeApiAdapter((options) {
          if (options.method == 'POST') {
            return FakeResponse.json(<String, Object?>{'id_str': '7'});
          }
          return FakeResponse.json(<String, Object?>{
            'id_str': '7',
            'status': 'still processing',
          });
        });
        final client = StravaClient(
          dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
          sleep: _noSleep,
        );

        final e = await integrationFailure(
          () => client.uploadAndWait(
            bytes: utf8.encode('<gpx/>'),
            dataType: StravaDataType.gpx,
            name: 'Morning loop',
          ),
        );
        expect(e.failure, IntegrationFailure.serviceError);
        expect(e.message, contains('still processing'));
      },
    );

    test('the backoff is 2, 4, 8 then 16 seconds', () {
      expect(StravaClient.uploadPollBackoff.take(4).toList(), const <Duration>[
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
      ]);
    });
  });

  group('routes', () {
    test('listRoutes reads the athlete page', () async {
      final adapter = FakeApiAdapter(
        (_) => FakeResponse.json(<Object?>[
          <String, Object?>{
            'id': 1,
            'id_str': '1',
            'name': 'Sunday loop',
            'distance': 42500.0,
            'elevation_gain': 620.0,
            'created_at': '2026-09-01T08:00:00Z',
          },
          <String, Object?>{'id_str': '2', 'name': 'Commute'},
        ]),
      );
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
      );

      final routes = await client.listRoutes(athleteId: '42', perPage: 10);

      expect(
        adapter.uris.single.path,
        '/proxy/strava/api/v3/athletes/42/routes',
      );
      expect(adapter.uris.single.queryParameters, <String, String>{
        'page': '1',
        'per_page': '10',
      });
      expect(routes, hasLength(2));
      expect(routes.first.name, 'Sunday loop');
      expect(routes.first.distanceM, 42500.0);
      expect(routes.first.elevationGainM, 620.0);
      expect(routes.first.createdAt, DateTime.utc(2026, 9, 1, 8));
      expect(routes.last.distanceM, 0);
    });

    test('exportRouteGpx returns the bytes', () async {
      final adapter = FakeApiAdapter(
        (_) => FakeResponse.text('<gpx version="1.1"></gpx>'),
      );
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
      );

      final bytes = await client.exportRouteGpx('9');

      expect(
        adapter.uris.single.path,
        '/proxy/strava/api/v3/routes/9/export_gpx',
      );
      expect(utf8.decode(bytes), contains('<gpx'));
    });

    test('an empty export is an error, not an empty route', () async {
      final adapter = FakeApiAdapter((_) => FakeResponse.text(''));
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
      );

      final e = await integrationFailure(() => client.exportRouteGpx('9'));
      expect(e.failure, IntegrationFailure.serviceError);
    });
  });

  group('failures', () {
    test('a 401 says the connection is no longer valid', () async {
      final adapter = FakeApiAdapter(
        (_) => FakeResponse.json(<String, Object?>{
          'message': 'Authorization Error',
        }, status: 401),
      );
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
      );

      final e = await integrationFailure(
        () => client.listRoutes(athleteId: '42'),
      );
      expect(e.failure, IntegrationFailure.notConnected);
      expect(e.message, contains('Connections'));
    });

    test('a 429 carries Strava\'s own retry hint', () async {
      final adapter = FakeApiAdapter(
        (_) => FakeResponse.json(<String, Object?>{}, status: 429),
      );
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
      );

      final e = await integrationFailure(
        () => client.listRoutes(athleteId: '42'),
      );
      expect(e.failure, IntegrationFailure.rateLimited);
    });

    test('a 500 shows the message Strava sent', () async {
      final adapter = FakeApiAdapter(
        (_) => FakeResponse.json(<String, Object?>{
          'message': 'Bad Request',
          'errors': <Object?>[
            <String, Object?>{
              'resource': 'Upload',
              'field': 'file',
              'code': 'invalid',
            },
          ],
        }, status: 500),
      );
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
      );

      final e = await integrationFailure(
        () => client.listRoutes(athleteId: '42'),
      );
      expect(e.failure, IntegrationFailure.serviceError);
      expect(e.message, contains('Bad Request'));
      expect(e.message, contains('file invalid'));
    });
  });

  group('the read bucket', () {
    test('stops the reads before Strava does', () async {
      var now = DateTime.utc(2026, 9, 12, 12);
      final adapter = FakeApiAdapter((_) => FakeResponse.json(<Object?>[]));
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
        readBucket: TokenBucket(
          capacity: 2,
          window: const Duration(minutes: 15),
          clock: () => now,
        ),
      );

      await client.listRoutes(athleteId: '42');
      await client.listRoutes(athleteId: '42');
      final e = await integrationFailure(
        () => client.listRoutes(athleteId: '42'),
      );

      expect(e.failure, IntegrationFailure.rateLimited);
      expect(e.message, contains('try again in'));
      // The third request never left the phone.
      expect(adapter.requests, hasLength(2));

      // A quarter of an hour later the window has slid past both calls.
      now = now.add(const Duration(minutes: 16));
      await client.listRoutes(athleteId: '42');
      expect(adapter.requests, hasLength(3));
    });

    test('an upload is a write and is not counted against it', () async {
      final adapter = FakeApiAdapter(
        (_) => FakeResponse.json(<String, Object?>{'id_str': '1'}),
      );
      final client = StravaClient(
        dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
        sleep: _noSleep,
        readBucket: TokenBucket(
          capacity: 1,
          window: const Duration(minutes: 15),
        ),
      );

      await client.uploadActivity(
        bytes: utf8.encode('<gpx/>'),
        dataType: StravaDataType.gpx,
        name: 'a',
      );
      await client.uploadActivity(
        bytes: utf8.encode('<gpx/>'),
        dataType: StravaDataType.gpx,
        name: 'b',
      );

      expect(adapter.requests, hasLength(2));
    });
  });

  test('deauthorize posts to the legacy endpoint with no token in the '
      'URL', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{'access_token': 'gone'}),
    );
    final client = StravaClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/strava'),
      sleep: _noSleep,
    );

    await client.deauthorize();

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    // The token rides in the interceptor's header, never in the query, so
    // it cannot end up in a log line.
    expect(
      '${request.uri}',
      'https://relay.test/proxy/strava/oauth/deauthorize',
    );
    expect(request.uri.queryParameters, isEmpty);
  });
}
