import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
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
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Moving'), findsOneWidget);
    expect(find.text('Ascent'), findsOneWidget);
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
}
