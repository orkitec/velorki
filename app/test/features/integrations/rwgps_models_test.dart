import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/rwgps/domain/rwgps_models.dart';

/// A task as `POST /api/v1/routes.json` and `GET /api/v1/tasks/{id}.json`
/// send it, wrapped in its `task` envelope.
Map<String, Object?> _task({
  String status = 'pending',
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

/// One route as `GET /api/v1/routes.json` sends it.
Map<String, Object?> _routeJson() => <String, Object?>{
  'id': 4242,
  'name': 'Sunday loop',
  'description': 'via the lake',
  'distance': 42123.4,
  'elevation_gain': 380.5,
  'created_at': '2026-09-12T18:02:13Z',
  'first_lat_lng': <String, Object?>{'lat': 48.14, 'lng': 11.58},
};

void main() {
  group('what an upload task created', () {
    test('a created route links to its page on Ride with GPS', () {
      final item = RwgpsTaskItem.fromJson(<String, Object?>{
        'item_type': 'route',
        'item_id': 4242,
        'item_url': 'https://ridewithgps.com/api/v1/routes/4242.json',
      });

      expect(item.itemType, 'route');
      expect(item.itemId, '4242');
      expect(item.itemUrl, 'https://ridewithgps.com/api/v1/routes/4242.json');
      expect(item.webUrl, 'https://ridewithgps.com/routes/4242');
    });

    test('a created trip links to the trip page instead', () {
      final item = RwgpsTaskItem.fromJson(<String, Object?>{
        'item_type': 'trip',
        'item_id': 99,
      });

      expect(item.webUrl, 'https://ridewithgps.com/trips/99');
      expect(item.itemUrl, isNull);
    });

    test('an item type the app does not know has no page to open', () {
      final item = RwgpsTaskItem.fromJson(<String, Object?>{
        'item_type': 'photo',
        'item_id': 1,
      });

      expect(item.webUrl, isNull);
    });

    test('an item with nothing in it is empty rather than broken', () {
      final item = RwgpsTaskItem.fromJson(<String, Object?>{});

      expect(item.itemType, '');
      expect(item.itemId, '');
      expect(item.itemUrl, isNull);
      expect(item.webUrl, isNull);
    });

    test('the description names the type and the id', () {
      final item = RwgpsTaskItem.fromJson(<String, Object?>{
        'item_type': 'route',
        'item_id': 4242,
      });

      expect(item.toString(), 'RwgpsTaskItem(route 4242)');
    });
  });

  group('what went wrong in a task', () {
    test('a duplicate points at the ride that is already there', () {
      final error = RwgpsTaskError.fromJson(<String, Object?>{
        'code': 'duplicate',
        'message': 'This ride is already on Ride with GPS.',
        'item_id': 4242,
      });

      expect(error.isDuplicate, isTrue);
      expect(error.isTimeDataMissing, isFalse);
      expect(error.itemId, '4242');
      expect(error.display, 'This ride is already on Ride with GPS.');
    });

    test('a file without timestamps cannot become a trip', () {
      final error = RwgpsTaskError.fromJson(<String, Object?>{
        'code': 'time_data_missing',
        'message': 'The file has no timestamps.',
      });

      expect(error.isTimeDataMissing, isTrue);
      expect(error.isDuplicate, isFalse);
      expect(error.itemId, isNull);
    });

    test('an error without a message shows its code instead', () {
      final error = RwgpsTaskError.fromJson(<String, Object?>{
        'code': 'parse_failed',
      });

      expect(error.message, '');
      expect(error.display, 'parse_failed');
    });

    test('an error with neither code nor message is still showable', () {
      final error = RwgpsTaskError.fromJson(<String, Object?>{});

      expect(error.code, 'error');
      expect(error.display, 'error');
    });

    test('the description names the code and the message', () {
      final error = RwgpsTaskError.fromJson(<String, Object?>{
        'code': 'duplicate',
        'message': 'already there',
      });

      expect(error.toString(), 'RwgpsTaskError(duplicate: already there)');
    });
  });

  group('reading an upload task', () {
    test('a pending task has an id and nothing else yet', () {
      final task = RwgpsTask.fromJson(_task());

      expect(task.id, '77');
      expect(task.status, 'pending');
      expect(task.isCompleted, isFalse);
      expect(task.items, isEmpty);
      expect(task.errors, isEmpty);
      expect(task.firstItem, isNull);
    });

    test('a completed task carries the asset it created', () {
      final task = RwgpsTask.fromJson(
        _task(
          status: 'completed',
          items: <Object?>[
            <String, Object?>{'item_type': 'route', 'item_id': 4242},
            <String, Object?>{'item_type': 'route', 'item_id': 4243},
          ],
        ),
      );

      expect(task.isCompleted, isTrue);
      expect(task.items, hasLength(2));
      expect(task.firstItem!.itemId, '4242');
    });

    test('a bare task object without the envelope reads the same', () {
      final task = RwgpsTask.fromJson(<String, Object?>{
        'id': 77,
        'status': 'completed',
        'items': <Object?>[
          <String, Object?>{'item_type': 'trip', 'item_id': 9},
        ],
      });

      expect(task.id, '77');
      expect(task.isCompleted, isTrue);
      expect(task.firstItem!.webUrl, 'https://ridewithgps.com/trips/9');
    });

    test('a task that says nothing is treated as still pending', () {
      final task = RwgpsTask.fromJson(<String, Object?>{});

      expect(task.id, '');
      expect(task.status, 'pending');
      expect(task.isCompleted, isFalse);
    });

    test('a status other than completed is not completed', () {
      expect(RwgpsTask.fromJson(_task(status: 'queued')).isCompleted, isFalse);
      expect(RwgpsTask.fromJson(_task(status: 'failed')).isCompleted, isFalse);
      expect(
        RwgpsTask.fromJson(_task(status: 'Completed')).isCompleted,
        isFalse,
      );
    });

    test('items and errors that are not lists are ignored', () {
      final task = RwgpsTask.fromJson(<String, Object?>{
        'id': 1,
        'status': 'completed',
        'items': 'none',
        'errors': <String, Object?>{'code': 'duplicate'},
      });

      expect(task.items, isEmpty);
      expect(task.errors, isEmpty);
    });

    test('entries that are not objects are skipped, not thrown', () {
      final task = RwgpsTask.fromJson(
        _task(
          status: 'completed',
          items: <Object?>[
            'route 1',
            null,
            <String, Object?>{'item_type': 'route', 'item_id': 4242},
          ],
          errors: <Object?>[
            7,
            <String, Object?>{'code': 'duplicate', 'message': 'already there'},
          ],
        ),
      );

      expect(task.items, hasLength(1));
      expect(task.items.single.itemId, '4242');
      expect(task.errors, hasLength(1));
      expect(task.errors.single.isDuplicate, isTrue);
    });

    test('a task can complete with errors and no items at all', () {
      final task = RwgpsTask.fromJson(
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

      expect(task.isCompleted, isTrue);
      expect(task.firstItem, isNull);
      expect(task.errors.single.isTimeDataMissing, isTrue);
    });

    test('the description counts what the task produced', () {
      final task = RwgpsTask.fromJson(
        _task(
          status: 'completed',
          items: <Object?>[
            <String, Object?>{'item_type': 'route', 'item_id': 1},
          ],
        ),
      );

      expect(task.toString(), 'RwgpsTask(77, completed, 1 items, 0 errors)');
    });
  });

  group('reading a route', () {
    test('the numbers the route list shows are read as sent', () {
      final route = RwgpsRouteSummary.fromJson(_routeJson());

      expect(route.id, '4242');
      expect(route.name, 'Sunday loop');
      expect(route.description, 'via the lake');
      expect(route.distanceM, 42123.4);
      expect(route.elevationGainM, 380.5);
      expect(route.createdAt, DateTime.utc(2026, 9, 12, 18, 2, 13));
    });

    test('an integer distance becomes a double all the same', () {
      final route = RwgpsRouteSummary.fromJson(<String, Object?>{
        'id': 1,
        'distance': 42000,
        'elevation_gain': 380,
      });

      expect(route.distanceM, 42000.0);
      expect(route.elevationGainM, 380.0);
    });

    test('a route without a name or numbers still lists', () {
      final route = RwgpsRouteSummary.fromJson(<String, Object?>{});

      expect(route.id, '');
      expect(route.name, 'Route');
      expect(route.distanceM, 0);
      expect(route.elevationGainM, 0);
      expect(route.description, isNull);
      expect(route.createdAt, isNull);
    });

    test('an older route dates itself by its first recorded point', () {
      final route = RwgpsRouteSummary.fromJson(<String, Object?>{
        'id': 1,
        'first_lat_lng_created_at': '2019-04-01T06:30:00Z',
      });

      expect(route.createdAt, DateTime.utc(2019, 4, 1, 6, 30));
    });

    test('created_at wins over the first recorded point', () {
      final route = RwgpsRouteSummary.fromJson(<String, Object?>{
        'id': 1,
        'created_at': '2026-09-12T18:02:13Z',
        'first_lat_lng_created_at': '2019-04-01T06:30:00Z',
      });

      expect(route.createdAt, DateTime.utc(2026, 9, 12, 18, 2, 13));
    });

    test('a date that cannot be read is dropped, not thrown', () {
      final route = RwgpsRouteSummary.fromJson(<String, Object?>{
        'id': 1,
        'created_at': 'last Tuesday',
      });

      expect(route.createdAt, isNull);
    });

    test('a summary survives the round trip through the cache', () {
      final original = RwgpsRouteSummary.fromJson(_routeJson());

      final read = RwgpsRouteSummary.fromJson(original.toJson());

      expect(read, original);
      expect(read.description, original.description);
      expect(read.createdAt, original.createdAt);
    });

    test('the cache document leaves out what was never there', () {
      final route = RwgpsRouteSummary.fromJson(<String, Object?>{'id': 7});

      expect(route.toJson(), <String, Object?>{
        'id': '7',
        'name': 'Route',
        'distance': 0.0,
        'elevation_gain': 0.0,
      });
    });

    test('the same id, name and numbers is the same route', () {
      final a = RwgpsRouteSummary.fromJson(_routeJson());
      final b = RwgpsRouteSummary.fromJson(_routeJson());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(<RwgpsRouteSummary>{a, b}, hasLength(1));
    });

    test('a renamed or re-measured route is a different route', () {
      final route = RwgpsRouteSummary.fromJson(_routeJson());

      expect(
        route,
        isNot(RwgpsRouteSummary.fromJson(_routeJson()..['id'] = 1)),
      );
      expect(
        route,
        isNot(RwgpsRouteSummary.fromJson(_routeJson()..['name'] = 'Monday')),
      );
      expect(
        route,
        isNot(RwgpsRouteSummary.fromJson(_routeJson()..['distance'] = 1)),
      );
      expect(
        route,
        isNot(RwgpsRouteSummary.fromJson(_routeJson()..['elevation_gain'] = 1)),
      );
    });

    test('only an edited description is not a different route', () {
      expect(
        RwgpsRouteSummary.fromJson(_routeJson()),
        RwgpsRouteSummary.fromJson(_routeJson()..['description'] = 'other'),
      );
    });

    test('a route is not equal to something else entirely', () {
      expect(RwgpsRouteSummary.fromJson(_routeJson()), isNot('Sunday loop'));
    });

    test('the description names the route', () {
      expect(
        RwgpsRouteSummary.fromJson(_routeJson()).toString(),
        'RwgpsRouteSummary(4242, Sunday loop)',
      );
    });
  });

  group('reading a trip', () {
    test('a recorded ride knows when it started', () {
      final trip = RwgpsTripSummary.fromJson(<String, Object?>{
        'id': 99,
        'name': 'Saturday',
        'distance': 30000.0,
        'departed_at': '2026-09-12T08:15:00Z',
        'created_at': '2026-09-12T19:00:00Z',
      });

      expect(trip.id, '99');
      expect(trip.name, 'Saturday');
      expect(trip.distanceM, 30000.0);
      expect(trip.departedAt, DateTime.utc(2026, 9, 12, 8, 15));
    });

    test('a trip with no departure falls back to when it was uploaded', () {
      final trip = RwgpsTripSummary.fromJson(<String, Object?>{
        'id': 99,
        'created_at': '2026-09-12T19:00:00Z',
      });

      expect(trip.departedAt, DateTime.utc(2026, 9, 12, 19));
    });

    test('a trip without a name is simply a ride', () {
      final trip = RwgpsTripSummary.fromJson(<String, Object?>{});

      expect(trip.id, '');
      expect(trip.name, 'Ride');
      expect(trip.distanceM, 0);
      expect(trip.departedAt, isNull);
    });

    test('a date that cannot be read is dropped, not thrown', () {
      final trip = RwgpsTripSummary.fromJson(<String, Object?>{
        'id': 1,
        'departed_at': 'yesterday',
      });

      expect(trip.departedAt, isNull);
    });

    test('the description names the trip', () {
      final trip = RwgpsTripSummary.fromJson(<String, Object?>{
        'id': 99,
        'name': 'Saturday',
      });

      expect(trip.toString(), 'RwgpsTripSummary(99, Saturday)');
    });
  });

  group('reading the connected user', () {
    test('the envelope Ride with GPS wraps the user in is unwrapped', () {
      final user = RwgpsUser.fromJson(<String, Object?>{
        'user': <String, Object?>{
          'id': 1234,
          'name': 'Steffen',
          'email': 'nobody@example.com',
        },
      });

      expect(user.id, '1234');
      expect(user.name, 'Steffen');
    });

    test('a bare user object reads the same', () {
      final user = RwgpsUser.fromJson(<String, Object?>{
        'id': 1234,
        'name': 'Steffen',
      });

      expect(user.id, '1234');
      expect(user.name, 'Steffen');
    });

    test('a user without a name is still a user', () {
      final user = RwgpsUser.fromJson(<String, Object?>{'id': 1234});

      expect(user.id, '1234');
      expect(user.name, isNull);
      expect(user.toString(), 'RwgpsUser(1234, null)');
    });

    test('an answer with no user at all leaves the id empty', () {
      expect(RwgpsUser.fromJson(<String, Object?>{}).id, '');
    });
  });

  group('the web pages of Ride with GPS', () {
    test('a route and a trip each have their own address', () {
      expect(rwgpsRouteUrl('4242'), 'https://ridewithgps.com/routes/4242');
      expect(rwgpsTripUrl('99'), 'https://ridewithgps.com/trips/99');
    });
  });
}
