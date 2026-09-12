import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/integrations/application/ride_uploader.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/presentation/ride_upload_menu.dart';
import 'package:velorki/features/integrations/rwgps/data/rwgps_client.dart';
import 'package:velorki/features/integrations/strava/data/strava_client.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fake_dio.dart';
import 'support/pump.dart';

Future<void> _noSleep(Duration _) async {}

const ConnectedAccount _stravaAccount = ConnectedAccount(
  service: IntegrationService.strava,
  accessToken: 'access',
  athleteId: '42',
  athleteName: 'Steffen',
);

const ConnectedAccount _rwgpsAccount = ConnectedAccount(
  service: IntegrationService.rwgps,
  accessToken: 'rw',
  athleteId: '1',
  athleteName: 'Steffen',
);

List<TrackPoint> _track() => <TrackPoint>[
  for (var i = 0; i < 10; i++)
    TrackPoint(
      LatLng(48 + i * 0.001, 11),
      ele: 500 + i.toDouble(),
      time: DateTime.utc(2026, 9, 12, 10, 0, i * 10),
    ),
];

void main() {
  late VelorkiDatabase db;
  late RideRepository rides;

  setUp(() {
    db = VelorkiDatabase.memory();
    rides = RideRepository(db.ridesDao);
    addTearDown(db.close);
  });

  Future<Ride> seedRide() => rides.finalizeRide(
    rideId: 'ride-1',
    name: 'Morning loop',
    points: _track(),
    startedAt: DateTime.utc(2026, 9, 12, 10),
    endedAt: DateTime.utc(2026, 9, 12, 10, 1, 30),
  );

  RideUploader uploader(FakeApiAdapter strava) => RideUploader(
    rides: rides,
    strava: StravaClient(dio: dioWith(strava), sleep: _noSleep),
    rwgps: RwgpsClient(
      dio: dioWith(
        FakeApiAdapter((_) => FakeResponse.json(<String, Object?>{})),
      ),
      sleep: _noSleep,
    ),
  );

  testWidgets('offers only the services that are connected', (tester) async {
    final ride = await seedRide();
    await pumpIntegrations(
      tester,
      RideUploadMenu(ride: ride),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _stravaAccount,
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Upload to Strava'), findsOneWidget);
    expect(find.text('Upload to Ride with GPS'), findsNothing);
  });

  testWidgets('both connected services are offered', (tester) async {
    final ride = await seedRide();
    await pumpIntegrations(
      tester,
      RideUploadMenu(ride: ride),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _stravaAccount,
          IntegrationService.rwgps: _rwgpsAccount,
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Upload to Strava'), findsOneWidget);
    expect(find.text('Upload to Ride with GPS'), findsOneWidget);
  });

  testWidgets('nothing connected means no menu at all', (tester) async {
    final ride = await seedRide();
    await pumpIntegrations(tester, RideUploadMenu(ride: ride));

    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
  });

  testWidgets('an unentitled rider is not offered an upload', (tester) async {
    final ride = await seedRide();
    await pumpIntegrations(
      tester,
      RideUploadMenu(ride: ride),
      harness: IntegrationsHarness(
        entitled: false,
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _stravaAccount,
        },
      ),
    );

    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
  });

  testWidgets('uploading shows progress and then a View on Strava action', (
    tester,
  ) async {
    final ride = await seedRide();
    final strava = FakeApiAdapter((options) {
      if (options.method == 'POST') {
        return FakeResponse.json(<String, Object?>{'id_str': '77'});
      }
      return FakeResponse.json(<String, Object?>{
        'id_str': '77',
        'activity_id': 5555,
      });
    });
    final harness = await pumpIntegrations(
      tester,
      RideUploadMenu(ride: ride),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _stravaAccount,
        },
      ),
      extraOverrides: [
        rideUploaderProvider.overrideWithValue(uploader(strava)),
      ],
    );

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload to Strava'));
    await tester.pump();

    expect(find.text('Uploading to Strava…'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Uploaded to Strava'), findsOneWidget);
    expect(find.text('View on Strava'), findsOneWidget);

    await tester.tap(find.text('View on Strava'));
    await tester.pumpAndSettle();
    expect(
      harness.openedLinks.single.toString(),
      'https://www.strava.com/activities/5555',
    );

    // The ride now remembers where it went.
    final stored = await rides.rideById('ride-1');
    expect(stored!.uploadFor(IntegrationService.strava.id)!.activityId, '5555');
  });

  testWidgets('a failed upload says why', (tester) async {
    final ride = await seedRide();
    final strava = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{
        'message': 'Bad Request',
      }, status: 400),
    );
    await pumpIntegrations(
      tester,
      RideUploadMenu(ride: ride),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _stravaAccount,
        },
      ),
      extraOverrides: [
        rideUploaderProvider.overrideWithValue(uploader(strava)),
      ],
    );

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload to Strava'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Upload failed:'), findsOneWidget);
    expect(find.textContaining('Bad Request'), findsOneWidget);
  });

  testWidgets('a ride already on Strava is opened, not uploaded again', (
    tester,
  ) async {
    await seedRide();
    await rides.recordUpload(
      'ride-1',
      serviceId: IntegrationService.strava.id,
      upload: RideUpload(
        status: RideUploadStatus.done,
        uploadedAt: DateTime.utc(2026, 9, 12, 11),
        activityId: '5555',
        url: 'https://www.strava.com/activities/5555',
      ),
    );
    final ride = (await rides.rideById('ride-1'))!;
    final strava = FakeApiAdapter(
      (_) => FakeResponse.json(<String, Object?>{}),
    );
    final harness = await pumpIntegrations(
      tester,
      RideUploadMenu(ride: ride),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _stravaAccount,
        },
      ),
      extraOverrides: [
        rideUploaderProvider.overrideWithValue(uploader(strava)),
      ],
    );

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Upload to Strava'), findsNothing);
    expect(find.text('View on Strava'), findsOneWidget);

    await tester.tap(find.text('View on Strava'));
    await tester.pumpAndSettle();

    expect(
      harness.openedLinks.single.toString(),
      'https://www.strava.com/activities/5555',
    );
    // Nothing was sent to Strava.
    expect(strava.requests, isEmpty);
  });
}
