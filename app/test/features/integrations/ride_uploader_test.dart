import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/integrations/application/ride_uploader.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_client.dart';
import 'package:velorki/features/integrations/strava/data/strava_client.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fake_dio.dart';
import 'support/fakes.dart';

Future<void> _noSleep(Duration _) async {}

final DateTime _now = DateTime.utc(2026, 9, 12, 12);

List<TrackPoint> _timedTrack() => <TrackPoint>[
  for (var i = 0; i < 20; i++)
    TrackPoint(
      LatLng(48 + i * 0.001, 11),
      ele: 500 + i.toDouble(),
      time: DateTime.utc(2026, 9, 12, 10, 0, i * 10),
    ),
];

List<TrackPoint> _untimedTrack() => <TrackPoint>[
  for (var i = 0; i < 20; i++)
    TrackPoint(LatLng(48 + i * 0.001, 11), ele: 500 + i.toDouble()),
];

void main() {
  late VelorkiDatabase db;
  late RideRepository rides;

  setUp(() {
    db = VelorkiDatabase.memory();
    rides = RideRepository(db.ridesDao);
    addTearDown(db.close);
  });

  Future<Ride> seed({List<TrackPoint>? points}) => rides.finalizeRide(
    rideId: 'ride-1',
    name: 'Morning loop',
    points: points ?? _timedTrack(),
    startedAt: DateTime.utc(2026, 9, 12, 10),
    endedAt: DateTime.utc(2026, 9, 12, 10, 3, 10),
    notes: 'felt good',
  );

  RideUploader uploader({
    required FakeApiAdapter strava,
    required FakeApiAdapter rwgps,
  }) => RideUploader(
    rides: rides,
    strava: StravaClient(dio: dioWith(strava), sleep: _noSleep),
    rwgps: RwgpsClient(dio: dioWith(rwgps), sleep: _noSleep),
    clock: () => _now,
  );

  test('a Strava upload is remembered in the ride uploads column', () async {
    final ride = await seed();
    final strava = FakeApiAdapter((options) {
      if (options.method == 'POST') {
        return FakeResponse.json(<String, Object?>{'id_str': '77'});
      }
      return FakeResponse.json(<String, Object?>{
        'id_str': '77',
        'activity_id': 5555,
      });
    });
    final rwgps = FakeApiAdapter((_) => FakeResponse.json(<String, Object?>{}));

    final upload = await uploader(
      strava: strava,
      rwgps: rwgps,
    ).uploadToStrava(ride);

    expect(upload.activityId, '5555');
    expect(upload.url, 'https://www.strava.com/activities/5555');
    expect(upload.uploadedAt, _now);

    final reloaded = await rides.rideById('ride-1');
    final stored = reloaded!.uploadFor(IntegrationService.strava.id);
    expect(stored, isNotNull);
    expect(stored!.isDone, isTrue);
    expect(stored.activityId, '5555');

    // The external id is the ride's own id, so Strava recognises a second
    // upload of the same ride as a duplicate.
    expect(
      multipartFields(strava.requests.first)['external_id'],
      'velorki-ride-1',
    );
    expect(multipartFields(strava.requests.first)['data_type'], 'gpx');
    expect(multipartFields(strava.requests.first)['sport_type'], 'Ride');
    expect(multipartFields(strava.requests.first)['name'], 'Morning loop');
    expect(multipartFields(strava.requests.first)['description'], 'felt good');
  });

  test('a ride that is already on Strava is never uploaded twice', () async {
    var ride = await seed();
    final strava = FakeApiAdapter((options) {
      if (options.method == 'POST') {
        return FakeResponse.json(<String, Object?>{'id_str': '77'});
      }
      return FakeResponse.json(<String, Object?>{
        'id_str': '77',
        'activity_id': 5555,
      });
    });
    final rwgps = FakeApiAdapter((_) => FakeResponse.json(<String, Object?>{}));
    final up = uploader(strava: strava, rwgps: rwgps);

    await up.uploadToStrava(ride);
    ride = (await rides.rideById('ride-1'))!;

    final e = await integrationFailure(() => up.uploadToStrava(ride));
    expect(e.failure, IntegrationFailure.rejected);
    expect(e.message, contains('already on Strava'));
    // Nothing new left the phone: two calls from the first upload only.
    expect(strava.requests, hasLength(2));
  });

  test(
    'the GPX sent to Strava is a track with the ride\'s timestamps',
    () async {
      final ride = await seed();
      final gpx = utf8.decode(rideGpxBytes(ride));
      expect(gpx, contains('<trk>'));
      expect(gpx, contains('2026-09-12T10:00:00'));
      expect(gpx, contains('Morning loop'));
    },
  );

  test(
    'a Ride with GPS trip upload polls the task and stores the trip',
    () async {
      final ride = await seed();
      final strava = FakeApiAdapter(
        (_) => FakeResponse.json(<String, Object?>{}),
      );
      var polls = 0;
      final rwgps = FakeApiAdapter((options) {
        if (options.method == 'POST') {
          return FakeResponse.json(<String, Object?>{
            'task': <String, Object?>{'id': 9, 'status': 'pending'},
          }, status: 202);
        }
        polls++;
        return FakeResponse.json(<String, Object?>{
          'task': <String, Object?>{
            'id': 9,
            'status': polls < 2 ? 'pending' : 'completed',
            'items': polls < 2
                ? <Object?>[]
                : <Object?>[
                    <String, Object?>{'item_type': 'trip', 'item_id': 321},
                  ],
            'errors': <Object?>[],
          },
        });
      });

      final upload = await uploader(
        strava: strava,
        rwgps: rwgps,
      ).uploadToRwgps(ride);

      expect(upload.activityId, '321');
      expect(upload.url, 'https://ridewithgps.com/trips/321');
      final reloaded = await rides.rideById('ride-1');
      expect(
        reloaded!.uploadFor(IntegrationService.rwgps.id)!.activityId,
        '321',
      );
      // Strava's record is untouched by a Ride with GPS upload.
      expect(reloaded.uploadFor(IntegrationService.strava.id), isNull);
    },
  );

  test('an untimed track is refused before it is sent as a trip', () async {
    final ride = await seed(points: _untimedTrack());
    final strava = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{}),
    );
    final rwgps = FakeApiAdapter((_) => FakeResponse.json(<String, Object?>{}));

    final e = await integrationFailure(
      () => uploader(strava: strava, rwgps: rwgps).uploadToRwgps(ride),
    );
    expect(e.failure, IntegrationFailure.rejected);
    expect(e.message, contains('timestamps'));
    expect(rwgps.requests, isEmpty);
  });

  test('a Strava rejection leaves no upload record behind', () async {
    final ride = await seed();
    final strava = FakeApiAdapter((options) {
      if (options.method == 'POST') {
        return FakeResponse.json(<String, Object?>{'id_str': '77'});
      }
      return FakeResponse.json(<String, Object?>{
        'id_str': '77',
        'error': 'Your activity is a duplicate of 1.',
      });
    });
    final rwgps = FakeApiAdapter((_) => FakeResponse.json(<String, Object?>{}));

    final e = await integrationFailure(
      () => uploader(strava: strava, rwgps: rwgps).uploadToStrava(ride),
    );
    expect(e.failure, IntegrationFailure.rejected);
    expect(
      (await rides.rideById('ride-1'))!.uploadFor(IntegrationService.strava.id),
      isNull,
    );
  });

  test('both services can be recorded on the same ride', () async {
    await seed();
    await rides.recordUpload(
      'ride-1',
      serviceId: 'strava',
      upload: RideUpload(
        status: RideUploadStatus.done,
        uploadedAt: _now,
        activityId: '1',
      ),
    );
    await rides.recordUpload(
      'ride-1',
      serviceId: 'rwgps',
      upload: RideUpload(
        status: RideUploadStatus.done,
        uploadedAt: _now,
        activityId: '2',
      ),
    );

    final ride = await rides.rideById('ride-1');
    expect(ride!.uploads.keys, containsAll(<String>['strava', 'rwgps']));

    await rides.clearUpload('ride-1', serviceId: 'strava');
    expect((await rides.rideById('ride-1'))!.uploads.keys, <String>['rwgps']);
  });
}
