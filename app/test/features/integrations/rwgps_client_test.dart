import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_client.dart';

import 'support/fake_dio.dart';
import 'support/fakes.dart';

Future<void> _noSleep(Duration _) async {}

Map<String, Object?> _task({
  required String status,
  List<Object?> items = const <Object?>[],
  List<Object?> errors = const <Object?>[],
}) => <String, Object?>{
  'task': <String, Object?>{
    'id': 77,
    'type': 'gps_file_upload',
    'status': status,
    'items': items,
    'errors': errors,
  },
};

void main() {
  test('uploadRoute posts multipart file/name/description', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.json(_task(status: 'pending'), status: 202),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final task = await client.uploadRoute(
      gpxBytes: utf8.encode('<gpx/>'),
      name: 'Sunday loop',
      description: 'via the lake',
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    // Relative to the relay's pass-through, which forwards the same path.
    expect(
      '${request.uri}',
      'https://relay.test/proxy/rwgps/api/v1/routes.json',
    );
    expect(multipartFileNames(request), <String>['file']);
    expect(multipartFields(request), <String, String>{
      'name': 'Sunday loop',
      'description': 'via the lake',
    });
    expect(task.id, '77');
    expect(task.isCompleted, isFalse);
  });

  test('the task is polled until it completes and yields the route', () async {
    var polls = 0;
    final adapter = FakeApiAdapter((options) {
      if (options.method == 'POST') {
        return FakeResponse.json(_task(status: 'pending'), status: 202);
      }
      polls++;
      return FakeResponse.json(
        polls < 3
            ? _task(status: 'pending')
            : _task(
                status: 'completed',
                items: <Object?>[
                  <String, Object?>{
                    'item_type': 'route',
                    'item_id': 4242,
                    'item_url':
                        'https://ridewithgps.com/api/v1/routes/4242.json',
                  },
                ],
              ),
      );
    });
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final task = await client.uploadRouteAndWait(
      gpxBytes: utf8.encode('<gpx/>'),
      name: 'Sunday loop',
    );

    expect(polls, 3);
    expect(adapter.uris.last.path, '/proxy/rwgps/api/v1/tasks/77.json');
    expect(task.isCompleted, isTrue);
    expect(task.firstItem!.itemId, '4242');
    expect(task.firstItem!.itemType, 'route');
    expect(task.firstItem!.webUrl, 'https://ridewithgps.com/routes/4242');
  });

  test('a completed task with only errors is a rejection', () async {
    final adapter = FakeApiAdapter((options) {
      if (options.method == 'POST') {
        return FakeResponse.json(_task(status: 'pending'), status: 202);
      }
      return FakeResponse.json(
        _task(
          status: 'completed',
          errors: <Object?>[
            <String, Object?>{
              'code': 'time_data_missing',
              'message': 'The file has no timestamps.',
            },
          ],
        ),
      );
    });
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final e = await integrationFailure(
      () => client.uploadTripAndWait(
        gpxBytes: utf8.encode('<gpx/>'),
        name: 'Ride',
      ),
    );
    expect(e.failure, IntegrationFailure.rejected);
    expect(e.message, contains('no timestamps'));
  });

  test('a task that never completes is reported', () async {
    final adapter = FakeApiAdapter(
      (options) => FakeResponse.json(
        _task(status: 'pending'),
        status: options.method == 'POST' ? 202 : 200,
      ),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final e = await integrationFailure(
      () => client.uploadRouteAndWait(
        gpxBytes: utf8.encode('<gpx/>'),
        name: 'Sunday loop',
      ),
    );
    expect(e.failure, IntegrationFailure.serviceError);
  });

  test('uploadTrip posts to trips.json', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.json(
        _task(
          status: 'completed',
          items: <Object?>[
            <String, Object?>{'item_type': 'trip', 'item_id': 9},
          ],
        ),
        status: 202,
      ),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final task = await client.uploadTripAndWait(
      gpxBytes: utf8.encode('<gpx/>'),
      name: 'Morning loop',
    );

    expect(
      '${adapter.uris.single}',
      'https://relay.test/proxy/rwgps/api/v1/trips.json',
    );
    expect(task.firstItem!.webUrl, 'https://ridewithgps.com/trips/9');
  });

  test('listRoutes reads the routes array and its paging query', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{
        'routes': <Object?>[
          <String, Object?>{
            'id': 1,
            'name': 'Sunday loop',
            'distance': 42500.0,
            'elevation_gain': 620.0,
            'created_at': '2026-09-01T08:00:00Z',
          },
        ],
        'meta': <String, Object?>{
          'pagination': <String, Object?>{'page': 1},
        },
      }),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final routes = await client.listRoutes(pageSize: 20);

    expect(adapter.uris.single.path, '/proxy/rwgps/api/v1/routes.json');
    expect(adapter.uris.single.queryParameters, <String, String>{
      'page': '1',
      'page_size': '20',
    });
    expect(routes.single.name, 'Sunday loop');
    expect(routes.single.distanceM, 42500.0);
  });

  test('listTrips reads the trips array', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{
        'trips': <Object?>[
          <String, Object?>{
            'id': 5,
            'name': 'Commute',
            'distance': 8000.0,
            'departed_at': '2026-09-11T07:30:00Z',
          },
        ],
      }),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final trips = await client.listTrips();

    expect(adapter.uris.single.path, '/proxy/rwgps/api/v1/trips.json');
    expect(trips.single.id, '5');
    expect(trips.single.departedAt, DateTime.utc(2026, 9, 11, 7, 30));
  });

  test('routeGpx downloads the .gpx representation', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.text('<gpx version="1.1"></gpx>'),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final bytes = await client.routeGpx('4242');

    expect(adapter.uris.single.path, '/proxy/rwgps/api/v1/routes/4242.gpx');
    expect(utf8.decode(bytes), contains('<gpx'));
  });

  test('currentUser reads the wrapped user object', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{
        'user': <String, Object?>{'id': 1, 'name': 'Steffen'},
      }),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final user = await client.currentUser();

    expect(adapter.uris.single.path, '/proxy/rwgps/api/v1/users/current.json');
    expect(user.id, '1');
    expect(user.name, 'Steffen');
  });

  test('a 401 says the connection is no longer valid', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{
        'errors': <Object?>['Unauthorized'],
      }, status: 401),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    final e = await integrationFailure(client.listRoutes);
    expect(e.failure, IntegrationFailure.notConnected);
  });

  test('revoke posts to the OAuth revoke path with an empty body', () async {
    final adapter = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{}),
    );
    final client = RwgpsClient(
      dio: dioWith(adapter, baseUrl: '$testProxyBase/rwgps'),
      sleep: _noSleep,
    );

    await client.revoke();

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      '${request.uri}',
      'https://relay.test/proxy/rwgps/oauth/revoke.json',
    );
    expect(request.data, isNull);
  });
}
