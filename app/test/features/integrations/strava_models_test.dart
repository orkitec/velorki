import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/strava/domain/strava_models.dart';

/// One route as `GET /athletes/{id}/routes` sends it, trimmed to the fields
/// the app reads plus a few it must ignore.
Map<String, Object?> _routeJson() => <String, Object?>{
  'id': 4567890123456789,
  'id_str': '4567890123456789',
  'name': 'Isar loop',
  'description': 'flat, mostly gravel',
  'distance': 42123.4,
  'elevation_gain': 380.5,
  'created_at': '2026-09-12T18:02:13Z',
  'type': 1,
  'sub_type': 1,
  'private': false,
  'map': <String, Object?>{
    'id': 'r4567890123456789',
    'summary_polyline': '_p~',
  },
};

void main() {
  group('the file types Strava takes', () {
    test('the wire value is the multipart data_type field', () {
      expect(StravaDataType.gpx.wire, 'gpx');
      expect(StravaDataType.fit.wire, 'fit');
    });
  });

  group('reading an upload', () {
    test('the answer to a fresh POST is still pending', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id': 1234,
        'id_str': '1234',
        'external_id': 'velorki-ride-1',
        'error': null,
        'status': 'Your activity is still being processed.',
        'activity_id': null,
      });

      expect(upload.id, '1234');
      expect(upload.externalId, 'velorki-ride-1');
      expect(upload.status, 'Your activity is still being processed.');
      expect(upload.pending, isTrue);
      expect(upload.succeeded, isFalse);
      expect(upload.failed, isFalse);
      expect(upload.activityId, isNull);
      expect(upload.activityUrl, isNull);
    });

    test('a finished upload names the activity it became', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id_str': '1234',
        'status': 'Your activity is ready.',
        'activity_id': 14321234567890,
      });

      expect(upload.succeeded, isTrue);
      expect(upload.pending, isFalse);
      expect(upload.activityId, '14321234567890');
      expect(
        upload.activityUrl,
        'https://www.strava.com/activities/14321234567890',
      );
    });

    test('a rejected upload carries Strava\'s own wording', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id_str': '7',
        'error': 'Your activity is a duplicate of 12345.',
        'status': 'There was an error processing your activity.',
      });

      expect(upload.failed, isTrue);
      expect(upload.pending, isFalse);
      expect(upload.succeeded, isFalse);
      expect(upload.error, contains('duplicate'));
      expect(upload.activityUrl, isNull);
    });

    test('the string id is preferred over the number, so nothing is lost', () {
      // 9007199254740993 has no exact double, which is what id_str is for.
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id': 9007199254740993,
        'id_str': '9007199254740993',
      });

      expect(upload.id, '9007199254740993');
    });

    test('a numeric id alone is still read', () {
      expect(StravaUpload.fromJson(<String, Object?>{'id': 42}).id, '42');
    });

    test('an empty id_str falls back to the numeric id', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id_str': '',
        'id': 42,
      });

      expect(upload.id, '42');
    });

    test('an answer with no id at all leaves the id empty', () {
      final upload = StravaUpload.fromJson(<String, Object?>{});

      expect(upload.id, '');
      expect(upload.externalId, isNull);
      expect(upload.status, isNull);
      expect(upload.pending, isTrue);
    });

    test('an activity object is read when there is no activity_id', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id_str': '7',
        'activity': <String, Object?>{'id': 5555, 'name': 'Morning loop'},
      });

      expect(upload.activityId, '5555');
      expect(upload.succeeded, isTrue);
    });

    test('activity_id wins over a nested activity object', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id_str': '7',
        'activity_id': 1,
        'activity': <String, Object?>{'id': 2},
      });

      expect(upload.activityId, '1');
    });

    test('an empty error string is not a failure', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id_str': '7',
        'error': '',
      });

      expect(upload.failed, isFalse);
      expect(upload.pending, isTrue);
    });

    test('an empty activity_id is not a success', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id_str': '7',
        'activity_id': '',
      });

      expect(upload.succeeded, isFalse);
      expect(upload.activityUrl, isNull);
    });

    test('a numeric id_str, which Strava should never send, is tolerated', () {
      expect(StravaUpload.fromJson(<String, Object?>{'id_str': 42}).id, '42');
    });

    test('the description names the upload and what became of it', () {
      final upload = StravaUpload.fromJson(<String, Object?>{
        'id_str': '7',
        'activity_id': 9,
      });

      expect(upload.toString(), 'StravaUpload(7, activity: 9, error: null)');
    });
  });

  group('the web pages of Strava', () {
    test('an activity and a route each have their own address', () {
      expect(
        stravaActivityUrl('5555'),
        'https://www.strava.com/activities/5555',
      );
      expect(stravaRouteUrl('123'), 'https://www.strava.com/routes/123');
    });
  });

  group('reading a route', () {
    test('the four numbers the route list shows are read as sent', () {
      final route = StravaRouteSummary.fromJson(_routeJson());

      expect(route.id, '4567890123456789');
      expect(route.name, 'Isar loop');
      expect(route.description, 'flat, mostly gravel');
      expect(route.distanceM, 42123.4);
      expect(route.elevationGainM, 380.5);
      expect(route.createdAt, DateTime.utc(2026, 9, 12, 18, 2, 13));
    });

    test('an integer distance becomes a double all the same', () {
      final route = StravaRouteSummary.fromJson(<String, Object?>{
        'id_str': '1',
        'distance': 42000,
        'elevation_gain': 380,
      });

      expect(route.distanceM, 42000.0);
      expect(route.elevationGainM, 380.0);
    });

    test('a route without a name or numbers still lists', () {
      final route = StravaRouteSummary.fromJson(<String, Object?>{'id': 7});

      expect(route.id, '7');
      expect(route.name, 'Route');
      expect(route.distanceM, 0);
      expect(route.elevationGainM, 0);
      expect(route.description, isNull);
      expect(route.createdAt, isNull);
    });

    test('null fields read the same as absent ones', () {
      final route = StravaRouteSummary.fromJson(<String, Object?>{
        'id_str': '7',
        'name': null,
        'description': null,
        'distance': null,
        'elevation_gain': null,
        'created_at': null,
      });

      expect(route.name, 'Route');
      expect(route.distanceM, 0);
      expect(route.elevationGainM, 0);
      expect(route.description, isNull);
      expect(route.createdAt, isNull);
    });

    test('a date Strava could not have sent is dropped, not thrown', () {
      final route = StravaRouteSummary.fromJson(<String, Object?>{
        'id_str': '7',
        'created_at': 'last Tuesday',
      });

      expect(route.createdAt, isNull);
    });

    test('a route with neither id is listed under an empty id', () {
      expect(StravaRouteSummary.fromJson(<String, Object?>{}).id, '');
    });

    test('the numeric id is used when there is no id_str', () {
      expect(
        StravaRouteSummary.fromJson(<String, Object?>{'id': 4567}).id,
        '4567',
      );
    });
  });

  group('caching a route list', () {
    test('a summary survives the round trip through the cache', () {
      final original = StravaRouteSummary.fromJson(_routeJson());

      final read = StravaRouteSummary.fromJson(original.toJson());

      expect(read, original);
      expect(read.id, original.id);
      expect(read.description, original.description);
      expect(read.createdAt, original.createdAt);
    });

    test('the cache document leaves out what was never there', () {
      final route = StravaRouteSummary.fromJson(<String, Object?>{'id': 7});

      expect(route.toJson(), <String, Object?>{
        'id_str': '7',
        'name': 'Route',
        'distance': 0.0,
        'elevation_gain': 0.0,
      });
    });

    test('the date is written in ISO 8601', () {
      final route = StravaRouteSummary.fromJson(_routeJson());

      expect(route.toJson()['created_at'], '2026-09-12T18:02:13.000Z');
    });
  });

  group('telling two routes apart', () {
    test('the same id, name and numbers is the same route', () {
      final a = StravaRouteSummary.fromJson(_routeJson());
      final b = StravaRouteSummary.fromJson(_routeJson());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(<StravaRouteSummary>{a, b}, hasLength(1));
    });

    test('a renamed or re-measured route is a different route', () {
      final route = StravaRouteSummary.fromJson(_routeJson());
      final json = _routeJson();

      expect(
        route,
        isNot(
          StravaRouteSummary.fromJson(json..['name'] = 'Isar loop, longer'),
        ),
      );
      expect(
        route,
        isNot(StravaRouteSummary.fromJson(_routeJson()..['distance'] = 1)),
      );
      expect(
        route,
        isNot(
          StravaRouteSummary.fromJson(_routeJson()..['elevation_gain'] = 1),
        ),
      );
      expect(
        route,
        isNot(StravaRouteSummary.fromJson(_routeJson()..['id_str'] = '1')),
      );
    });

    test('only an edited description is not a different route', () {
      final route = StravaRouteSummary.fromJson(_routeJson());

      expect(
        route,
        StravaRouteSummary.fromJson(_routeJson()..['description'] = 'other'),
      );
    });

    test('a route is not equal to something else entirely', () {
      expect(StravaRouteSummary.fromJson(_routeJson()), isNot('Isar loop'));
    });

    test('the description names the route', () {
      expect(
        StravaRouteSummary.fromJson(_routeJson()).toString(),
        'StravaRouteSummary(4567890123456789, Isar loop)',
      );
    });
  });
}
