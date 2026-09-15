import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki/features/recording/presentation/ride_detail_screen.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/pump.dart';

List<TrackPoint> _track() => <TrackPoint>[
  for (var i = 0; i < 60; i++)
    TrackPoint(
      LatLng(48 + i * 0.0002, 11),
      ele: 500 + (i < 30 ? i * 2.0 : (60 - i) * 2.0),
      time: DateTime.utc(2026, 9, 12, 10, 0, i),
    ),
];

Future<void> _seed(RecordingHarness harness) =>
    RideRepository(harness.planner.db.ridesDao).finalizeRide(
      rideId: 'ride-1',
      name: 'Morning loop',
      points: _track(),
      startedAt: DateTime.utc(2026, 9, 12, 10),
      endedAt: DateTime.utc(2026, 9, 12, 10, 0, 59),
    );

/// Opens the ride's overflow menu and picks "Continue this ride".
Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue this ride').last);
  await tester.pumpAndSettle();
  // Handing the ride back reads the journal off the real file system, which
  // only a real turn of the event loop finishes.
  await settleAsync(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the track, the statistics and the export buttons', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    expect(find.text('Morning loop'), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('MOVING'), findsOneWidget);
    expect(find.text('ASCENT'), findsOneWidget);
    expect(find.text('00:59'), findsWidgets);
    expect(find.text('Export GPX track'), findsWidgets);
    expect(find.text('Export FIT activity'), findsWidgets);

    // The track went on the map and the camera was fitted to it.
    final track = harness.map.calls.where((c) => c.method == 'setTrackLine');
    expect(track, isNotEmpty);
    expect((track.last.arguments.first as List<LatLng>?), hasLength(60));
    expect(harness.map.fittedBounds, isNotNull);
    expect(harness.map.fittedBounds!.south, closeTo(48, 1e-9));

    await unmountApp(tester);
  });

  testWidgets('a missing ride says so instead of crashing', (tester) async {
    await pumpRecordingScreen(tester, const RideDetailScreen(rideId: 'gone'));
    await tester.pumpAndSettle();

    expect(find.text('This ride no longer exists.'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the GPX button hands the ride to the exporter', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Export GPX track'));
    await tester.pumpAndSettle();

    expect(harness.exporter.exports, hasLength(1));
    final export = harness.exporter.exports.single;
    expect(export.name, 'Morning loop');
    expect(export.kind, TrackKind.ride);
    expect(export.format, TrackFormat.gpx);
    expect(export.points, hasLength(60));
    expect(export.startTime, DateTime.utc(2026, 9, 12, 10));

    await unmountApp(tester);
  });

  testWidgets('the menu exports a FIT activity', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export FIT activity').last);
    await tester.pumpAndSettle();

    expect(harness.exporter.exports.single.format, TrackFormat.fit);
    await unmountApp(tester);
  });

  testWidgets('a failing export says why', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    harness.exporter.error = const FormatException('no space left');
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Export GPX track'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Export failed:'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('continuing hands the ride back to the recorder', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await _tapContinue(tester);

    // Nothing else was recording and the ride was never sent anywhere, so
    // there is nothing to confirm.
    expect(harness.service.calls, <String>['continueRide(ride-1)']);
    expect(harness.service.continued.single.name, 'Morning loop');
    expect(find.byType(RideDetailScreen), findsNothing, reason: 'record tab');

    await unmountApp(tester);
  });

  testWidgets('continuing finishes a running recording first, once confirmed', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    harness.service.running = true;
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await _tapContinue(tester);
    expect(
      find.text(
        'Another ride is being recorded. It will be finished and '
        'saved first.',
      ),
      findsOneWidget,
    );
    expect(harness.service.calls, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue this ride'));
    await tester.pumpAndSettle();
    await settleAsync(tester);
    await tester.pumpAndSettle();

    expect(harness.service.calls, hasLength(2));
    expect(harness.service.calls.first, startsWith('stop(Ride '));
    expect(harness.service.calls.last, 'continueRide(ride-1)');

    await unmountApp(tester);
  });

  testWidgets('an uploaded ride says it will have to be sent again', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await RideRepository(harness.planner.db.ridesDao).recordUpload(
      'ride-1',
      serviceId: 'strava',
      upload: RideUpload(
        status: RideUploadStatus.done,
        uploadedAt: DateTime.utc(2026, 9, 12, 11),
        activityId: '99',
      ),
    );
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await _tapContinue(tester);
    expect(
      find.textContaining('It was already sent to Strava'),
      findsOneWidget,
    );

    // Backing out leaves the ride alone.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(harness.service.calls, isEmpty);
    expect(find.byType(RideDetailScreen), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('renaming writes the new name', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Sunday spin');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sunday spin'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the ride detail reads in miles, mph and feet under imperial', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
      extraOverrides: [imperialUnits],
    );
    await tester.pumpAndSettle();

    // The seeded track runs about 1.3 km up to 558 m and back down.
    expect(find.textContaining(' mi'), findsWidgets);
    expect(find.textContaining(' mph'), findsWidgets);
    expect(find.textContaining(' ft'), findsWidgets);
    expect(find.textContaining(' km'), findsNothing);
    expect(find.textContaining(' km/h'), findsNothing);

    await unmountApp(tester);
  });
}
