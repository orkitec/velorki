import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/core/geo/ride_stats.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/ride_detail_screen.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/pump.dart';

RecordingSnapshot _snapshot({
  RecordingStatus status = RecordingStatus.active,
  bool autoPaused = false,
  double distanceM = 12345,
  List<LatLng> newPoints = const <LatLng>[],
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: status,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: autoPaused,
  distanceM: distanceM,
  elapsed: const Duration(minutes: 42, seconds: 7),
  moving: const Duration(minutes: 40),
  speedMps: 6,
  avgSpeedMps: 5,
  ascentM: 210,
  descentM: 190,
  lastPosition: const LatLng(48.1, 11.2),
  accuracyM: 4,
  pointCount: 120,
  newPoints: newPoints,
);

Ride _ride() => Ride(
  id: 'ride-1',
  name: 'Ride 12 Sept 2026',
  startedAt: DateTime.utc(2026, 9, 12, 10),
  endedAt: DateTime.utc(2026, 9, 12, 11),
  stats: const RideStats(distanceM: 12345, movingTime: Duration(minutes: 40)),
  geometry: PackedTrack.encode(<TrackPoint>[
    TrackPoint(const LatLng(48, 11), time: DateTime.utc(2026, 9, 12, 10)),
    TrackPoint(
      const LatLng(48.001, 11),
      time: DateTime.utc(2026, 9, 12, 10, 0, 30),
    ),
  ]),
);

void main() {
  testWidgets('the idle tab offers a start button and the recent rides', (
    tester,
  ) async {
    await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    expect(find.text('Ready to ride'), findsOneWidget);
    expect(find.text('Start ride'), findsOneWidget);
    expect(find.text('RECENT RIDES'), findsOneWidget);
    expect(find.text('No rides yet.'), findsOneWidget);
    expect(find.text('Follow a route'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('the recent rides are listed under the start button', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await RideRepository(harness.planner.db.ridesDao).save(_ride());
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: harness,
    );
    await tester.pumpAndSettle();

    expect(find.text('Ride 12 Sept 2026'), findsOneWidget);
    expect(find.textContaining('12.3 km'), findsOneWidget);
    expect(find.text('No rides yet.'), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('starting asks for the location and then starts the recorder', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await tester.tap(find.text('Start ride'));
    await tester.pumpAndSettle();

    expect(h.service.calls, <String>['start(null)']);
    await unmountApp(tester);
  });

  testWidgets('a refused location permission stops the start', (tester) async {
    final h = await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: RecordingHarness(
        location: LocationPermissionStatus.deniedForever,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Start ride'));
    await tester.pumpAndSettle();

    expect(h.service.calls, isEmpty);
    expect(
      find.text('Velorki needs location access to record a ride.'),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('the battery explanation is shown once before the prompt', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: RecordingHarness(batteryIgnored: false),
    );
    await tester.pump();

    await tester.tap(find.text('Start ride'));
    await tester.pumpAndSettle();

    expect(find.text('Keep recording in the background'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(h.battery.requests, 1);
    expect(h.service.calls, <String>['start(null)']);
    await unmountApp(tester);
  });

  testWidgets('a snapshot switches to the live panel and drives the map', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(
      tester,
      h,
      _snapshot(newPoints: const [LatLng(48.0, 11.0), LatLng(48.1, 11.2)]),
    );

    expect(find.text('RECORDING'), findsOneWidget);
    expect(find.text('12.3 km'), findsOneWidget);
    expect(find.text('42:07'), findsOneWidget);
    expect(find.text('40:00'), findsOneWidget);
    expect(find.text('210 m'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);

    final track = h.map.calls.where((c) => c.method == 'setTrackLine').last;
    expect(track.arguments.first, hasLength(2));
    expect(h.map.calls.where((c) => c.method == 'setPosition'), isNotEmpty);

    await unmountApp(tester);
  });

  testWidgets('pause and resume reach the recorder', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(tester, h, _snapshot());
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(h.service.calls, contains('pause'));

    await emitSnapshot(tester, h, _snapshot(status: RecordingStatus.paused));
    expect(find.text('PAUSED'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(h.service.calls, contains('resume'));

    await unmountApp(tester);
  });

  testWidgets('an auto-paused recording says so', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(
      tester,
      h,
      _snapshot(status: RecordingStatus.paused, autoPaused: true),
    );

    expect(find.text('AUTO-PAUSED'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('finishing an empty ride says nothing was recorded', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(tester, h, _snapshot());
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(h.service.calls.last, startsWith('stop('));
    expect(find.text('Nothing was recorded.'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('finishing a ride opens its detail screen', (tester) async {
    final harness = RecordingHarness()..service.finishedRide = _ride();
    await RideRepository(harness.planner.db.ridesDao).save(_ride());
    await pumpRecordingApp(tester, harness: harness);
    await tester.pump();

    await emitSnapshot(tester, harness, _snapshot());
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(find.byType(RideDetailScreen), findsOneWidget);
    expect(find.text('Ride 12 Sept 2026'), findsWidgets);
    await unmountApp(tester);
  });

  testWidgets('the keep-screen-on toggle drives the wake lock', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await tester.tap(find.text('Keep screen on'));
    await tester.pumpAndSettle();
    expect(h.screenWake.enabled, isTrue);

    await tester.tap(find.text('Keep screen on'));
    await tester.pumpAndSettle();
    expect(h.screenWake.enabled, isFalse);

    await unmountApp(tester);
  });

  testWidgets('a running recorder is reattached without asking', (
    tester,
  ) async {
    final state = RecordingState(
      rideId: 'ride-1',
      startedAt: DateTime.utc(2026, 9, 12, 10),
      status: RecordingStatus.active,
    );
    final harness = RecordingHarness(recovery: ReattachRecording(state))
      ..service.reattaches = true;
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: harness,
    );
    await tester.pumpAndSettle();

    expect(harness.service.calls, <String>['reattach']);
    expect(find.text('Unfinished ride'), findsNothing);
    await unmountApp(tester);
  });

  group('the resume-or-finish dialog', () {
    RecordingHarness harnessWith({Ride? ride}) {
      final harness = RecordingHarness(
        recovery: InterruptedRecording(
          state: RecordingState(
            rideId: 'ride-1',
            startedAt: DateTime.utc(2026, 9, 12, 10),
            status: RecordingStatus.active,
          ),
          stats: const RideStats(
            distanceM: 12345,
            movingTime: Duration(minutes: 42),
          ),
        ),
      );
      harness.service.finishedRide = ride;
      return harness;
    }

    testWidgets('appears with what the journal holds', (tester) async {
      await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        harness: harnessWith(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unfinished ride'), findsOneWidget);
      expect(find.textContaining('12.3 km'), findsOneWidget);
      expect(find.textContaining('42 min'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('Resume continues the recording', (tester) async {
      final h = harnessWith();
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
      await tester.pumpAndSettle();
      await settleAsync(tester);

      expect(h.service.calls, <String>['resumeInterrupted(ride-1)']);
      await unmountApp(tester);
    });

    testWidgets('Finish turns it into a ride', (tester) async {
      final h = harnessWith();
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(h.service.calls, <String>['finishInterrupted(ride-1)']);
      await unmountApp(tester);
    });

    testWidgets('Discard throws it away', (tester) async {
      final h = harnessWith();
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(h.service.calls, <String>['discardInterrupted(ride-1)']);
      await unmountApp(tester);
    });
  });

  testWidgets('a recorder that refuses to start shows why', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    h.service.startError = const RecordingException('service timeout');
    await tester.pump();

    await tester.tap(find.text('Start ride'));
    await tester.pumpAndSettle();

    expect(
      find.text('Recording could not be started: service timeout'),
      findsOneWidget,
    );
    await unmountApp(tester);
  });
}
