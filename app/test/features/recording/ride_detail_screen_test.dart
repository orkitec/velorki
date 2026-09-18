import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/recording/presentation/ride_detail_screen.dart';
import 'package:velorki/features/recording/presentation/ride_splits.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
import 'support/pump.dart';

List<TrackPoint> _track() => <TrackPoint>[
  for (var i = 0; i < 60; i++)
    TrackPoint(
      LatLng(48 + i * 0.0002, 11),
      ele: 500 + (i < 30 ? i * 2.0 : (60 - i) * 2.0),
      time: DateTime.utc(2026, 9, 12, 10, 0, i),
    ),
];

/// Exactly 20 km/h for three kilometres, one fix a second: three whole
/// kilometre splits of three minutes each.
List<TrackPoint> _threeKilometres({
  bool withElevation = true,
  bool withSensors = false,
}) {
  const speedMps = 1000 / 180;
  var position = const LatLng(48, 11);
  return <TrackPoint>[
    for (var i = 0; i <= 540; i++)
      TrackPoint(
        i == 0 ? position : position = destinationPoint(position, 0, speedMps),
        ele: withElevation ? 400 + i * 0.1 : null,
        time: DateTime.utc(2026, 9, 12, 10).add(Duration(seconds: i)),
        heartRateBpm: withSensors ? 120 + i ~/ 20 : null,
        cadenceRpm: withSensors ? 85 : null,
        powerW: withSensors ? 200 : null,
      ),
  ];
}

/// Saves a ride of [points] and opens its detail screen.
Future<void> _open(
  WidgetTester tester,
  RecordingHarness harness,
  List<TrackPoint> points, {
  List<Override> extraOverrides = const <Override>[],
}) async {
  await RideRepository(harness.planner.db.ridesDao).finalizeRide(
    rideId: 'ride-1',
    name: 'Morning loop',
    points: points,
    startedAt: points.first.time!,
    endedAt: points.last.time!,
  );
  await pumpRecordingScreen(
    tester,
    const RideDetailScreen(rideId: 'ride-1'),
    harness: harness,
    extraOverrides: extraOverrides,
  );
  await tester.pumpAndSettle();
}

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
  await tester.tap(find.text(l10n.rideContinue).last);
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
    expect(find.text(l10n.statDistance.toUpperCase()), findsOneWidget);
    // Once in the tiles, once as a column of the splits table.
    expect(find.text(l10n.statMovingTime.toUpperCase()), findsNWidgets(2));
    expect(find.text(l10n.statAscent.toUpperCase()), findsNWidgets(2));
    expect(find.text('00:59'), findsWidgets);
    expect(find.text(l10n.rideDetailExportGpx), findsWidgets);
    expect(find.text(l10n.rideDetailExportFit), findsWidgets);

    // The track went on the map coloured by speed, and the camera was fitted
    // to it.
    final segments = harness.map.trackSegments;
    expect(segments, isNotEmpty);
    expect(
      segments.expand((s) => s.points).length,
      // Every fix is in a segment; the ones where the colour changes are in
      // two, so the line has no holes.
      greaterThanOrEqualTo(60),
    );
    expect(segments.map((s) => s.t), everyElement(inInclusiveRange(0, 1)));
    expect(harness.map.fittedBounds, isNotNull);
    expect(harness.map.fittedBounds!.south, closeTo(48, 1e-9));

    await unmountApp(tester);
  });

  testWidgets('a missing ride says so instead of crashing', (tester) async {
    await pumpRecordingScreen(tester, const RideDetailScreen(rideId: 'gone'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.rideDetailNotFound), findsOneWidget);
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

    await tester.tap(
      find.widgetWithText(OutlinedButton, l10n.rideDetailExportGpx),
    );
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
    await tester.tap(find.text(l10n.rideDetailExportFit).last);
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

    await tester.tap(
      find.widgetWithText(OutlinedButton, l10n.rideDetailExportGpx),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(l10n.rideDetailExportFailed('').trim()),
      findsOneWidget,
    );
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
    expect(find.text(l10n.rideContinueRunning), findsOneWidget);
    expect(harness.service.calls, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, l10n.rideContinue));
    await tester.pumpAndSettle();
    await settleAsync(tester);
    await tester.pumpAndSettle();

    expect(harness.service.calls, hasLength(2));
    expect(
      harness.service.calls.first,
      startsWith('stop(${l10n.recordingRideName('')}'.trimRight()),
    );
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
      find.textContaining(l10n.rideContinueUploaded('Strava')),
      findsOneWidget,
    );

    // Backing out leaves the ride alone.
    await tester.tap(find.widgetWithText(TextButton, l10n.commonCancel));
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
    await tester.tap(find.text(l10n.commonRename));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Sunday spin');
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
    await tester.pumpAndSettle();

    expect(find.text('Sunday spin'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the analysis draws an elevation chart, a speed chart and '
      'the splits', (tester) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());

    expect(find.byType(RideElevationChart), findsOneWidget);
    expect(find.byType(RideSpeedChart), findsOneWidget);
    expect(find.byType(RideSplitsTable), findsOneWidget);
    expect(find.text(l10n.elevationTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statSpeed.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.rideSplits.toUpperCase()), findsOneWidget);
    // The legend under the map.
    expect(find.byType(RideSpeedLegend), findsOneWidget);
    expect(find.text(l10n.rideSpeedSlow.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.rideSpeedFast.toUpperCase()), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a ride with a sensor shows its figures and its chart', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres(withSensors: true));

    expect(find.byType(RideHeartRateChart), findsOneWidget);
    expect(find.text(l10n.rideHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statAvgHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statMaxHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statAvgCadence.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statAvgPower.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.unitRpm('85')), findsOneWidget);
    expect(find.text(l10n.unitWatts('200')), findsOneWidget);
    // 120 bpm rising to 147: a mean of 133 and a maximum of 147.
    expect(find.text(l10n.unitBpm('133')), findsOneWidget);
    expect(find.text(l10n.unitBpm('147')), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a ride without a sensor shows none of that', (tester) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());

    expect(find.byType(RideHeartRateChart), findsNothing);
    expect(find.text(l10n.rideHeartRate.toUpperCase()), findsNothing);
    expect(find.text(l10n.statAvgHeartRate.toUpperCase()), findsNothing);
    expect(find.text(l10n.statAvgPower.toUpperCase()), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('a ride without heights shows no elevation chart', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres(withElevation: false));

    expect(find.byType(RideElevationChart), findsNothing);
    expect(find.text(l10n.elevationTitle.toUpperCase()), findsNothing);
    // The speed chart and the splits are still there.
    expect(find.text(l10n.statSpeed.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.rideSplits.toUpperCase()), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('three kilometres at 20 km/h are three splits of 3:00', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());

    expect(find.text(testSplitLength(1000)), findsNWidgets(3));
    expect(find.text('03:00'), findsNWidgets(3));
    expect(find.text(testSpeed(20000 / 3600)), findsWidgets);

    await unmountApp(tester);
  });

  testWidgets('the same ride splits into miles under imperial', (tester) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(),
      extraOverrides: [imperialUnits],
    );

    // 1.86 miles: one whole mile and the remainder, flagged by its own length.
    expect(
      find.text(testSplitLength(1609.344, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(
      find.text(testSplitLength(3000 - 1609.344, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(find.text('04:50'), findsOneWidget);
    expect(find.text('04:10'), findsOneWidget);

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
