import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/core/geo/ride_stats.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/ride_detail_screen.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart' show MapCall;
import 'support/pump.dart';

RecordingSnapshot _snapshot({
  RecordingStatus status = RecordingStatus.active,
  bool autoPaused = false,
  double distanceM = 12345,
  List<LatLng> newPoints = const <LatLng>[],
  LatLng lastPosition = const LatLng(48.1, 11.2),
  double? headingDeg,
  double speedMps = 6,
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: status,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: autoPaused,
  distanceM: distanceM,
  elapsed: const Duration(minutes: 42, seconds: 7),
  moving: const Duration(minutes: 40),
  speedMps: speedMps,
  headingDeg: headingDeg,
  avgSpeedMps: 5,
  ascentM: 210,
  descentM: 190,
  lastPosition: lastPosition,
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

  testWidgets('the planned route is drawn while no saved route is followed', (
    tester,
  ) async {
    final h = RecordingHarness();
    await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
    await tester.pump();
    expect(find.text('No route'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordingScreen)),
    );
    final planner = container.read(plannerControllerProvider.notifier);
    planner.addWaypoint(const LatLng(48.0, 11.0));
    planner.addWaypoint(const LatLng(48.1, 11.1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final drawn = h.map.calls.where((c) => c.method == 'setRouteLine');
    expect(drawn, isNotEmpty, reason: 'the plan is the route to ride');
    expect(find.text('The route on the Plan tab'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a way back onto the route is drawn in place of the plan', (
    tester,
  ) async {
    final h = RecordingHarness();
    await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordingScreen)),
    );
    final planner = container.read(plannerControllerProvider.notifier);
    planner.addWaypoint(const LatLng(48.0, 11.0));
    planner.addWaypoint(const LatLng(48.1, 11.1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    const detour = <LatLng>[LatLng(48.05, 11.2), LatLng(48.08, 11.25)];
    container
        .read(detourRouteProvider.notifier)
        .replace(
          const GuidedRoute(
            key: 'detour:1:2',
            line: detour,
            turns: <TurnHint>[],
          ),
        );
    await tester.pumpAndSettle();

    expect(h.map.lines[followedRouteLineId], detour);

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

  testWidgets('the navigation bar hides while a ride runs on this tab', (
    tester,
  ) async {
    final h = await pumpRecordingApp(tester);
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);

    await emitSnapshot(
      tester,
      h,
      _snapshot(newPoints: const [LatLng(48.0, 11.0), LatLng(48.1, 11.2)]),
    );

    expect(find.text('RECORDING'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

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
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Finish'), findsOneWidget);

    final track = h.map.calls.where((c) => c.method == 'setTrackLine').last;
    expect(track.arguments.first, hasLength(2));
    expect(h.map.calls.where((c) => c.method == 'setPosition'), isNotEmpty);

    await unmountApp(tester);
  });

  testWidgets('pause and resume reach the recorder', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(tester, h, _snapshot());
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(h.service.calls, contains('pause'));

    await emitSnapshot(tester, h, _snapshot(status: RecordingStatus.paused));
    expect(find.text('PAUSED'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume'));
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
    await tester.tap(find.byTooltip('Finish'));
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
    await tester.tap(find.byTooltip('Finish'));
    await tester.pumpAndSettle();

    expect(find.byType(RideDetailScreen), findsOneWidget);
    expect(find.text('Ride 12 Sept 2026'), findsWidgets);
    await unmountApp(tester);
  });

  testWidgets('a late snapshot after finishing does not revive the ride', (
    tester,
  ) async {
    final harness = RecordingHarness()..service.finishedRide = _ride();
    await RideRepository(harness.planner.db.ridesDao).save(_ride());
    await pumpRecordingApp(tester, harness: harness);
    await tester.pump();

    await emitSnapshot(tester, harness, _snapshot());
    await tester.tap(find.byTooltip('Finish'));
    await tester.pumpAndSettle();
    expect(find.byType(RideDetailScreen), findsOneWidget);

    // The foreground isolate flushes one last time after the stop; the
    // Record tab must stay ready for the next ride, not go live again.
    await emitSnapshot(tester, harness, _snapshot());
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    expect(find.text('Ready to ride'), findsOneWidget);
    expect(find.text('RECORDING'), findsNothing);
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

  group('the map follows the rider', () {
    /// Every camera move the screen asked for, in order.
    List<MapCall> moves(RecordingHarness h) =>
        h.map.calls.where((c) => c.method == 'moveTo').toList();

    /// The idle the screen's own follow move ends in.
    Future<void> settleCamera(WidgetTester tester, RecordingHarness h) async {
      h.map.onCameraIdle?.call();
      await tester.pump();
    }

    testWidgets('a fix moves the camera once a ride runs', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      expect(moves(h), isEmpty, reason: 'an idle map stays where it is');

      await emitSnapshot(tester, h, _snapshot());

      expect(moves(h), hasLength(1));
      expect(moves(h).single.arguments.first, const LatLng(48.1, 11.2));
      expect(moves(h).single.arguments[1], followZoom);

      await settleCamera(tester, h);
      await emitSnapshot(
        tester,
        h,
        _snapshot(lastPosition: const LatLng(48.2, 11.3)),
      );

      expect(moves(h), hasLength(2));
      expect(moves(h).last.arguments.first, const LatLng(48.2, 11.3));

      await unmountApp(tester);
    });

    testWidgets('a camera that is already closer keeps its zoom', (
      tester,
    ) async {
      final h = RecordingHarness()..map.zoom = 18;
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot());

      expect(moves(h).single.arguments[1], 18);
      await unmountApp(tester);
    });

    testWidgets('panning the map by hand stops the following', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      // The idle our own move ends in is not the rider's doing.
      await settleCamera(tester, h);
      expect(moves(h), hasLength(1));

      // Now the rider drags the map somewhere else and lets go.
      h.map.center = const LatLng(48.6, 11.9);
      await settleCamera(tester, h);

      await emitSnapshot(
        tester,
        h,
        _snapshot(lastPosition: const LatLng(48.2, 11.3)),
      );

      expect(moves(h), hasLength(1), reason: 'the map is the rider\'s now');
      await unmountApp(tester);
    });

    testWidgets('a nudge inside the threshold keeps the following', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      await settleCamera(tester, h);

      // Twenty metres north of the fix: an animated move rarely lands on the
      // exact centre, and that must not read as a pan.
      h.map.center = const LatLng(48.10018, 11.2);
      await settleCamera(tester, h);

      await emitSnapshot(
        tester,
        h,
        _snapshot(lastPosition: const LatLng(48.2, 11.3)),
      );

      expect(moves(h), hasLength(2));
      await unmountApp(tester);
    });

    testWidgets('the locate button picks the following up again', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      await settleCamera(tester, h);
      h.map.center = const LatLng(48.6, 11.9);
      await settleCamera(tester, h);

      // What MapControls calls after it moved the camera to the fix.
      final chrome = tester.widget<MapChromeInsets>(
        find.byType(MapChromeInsets).first,
      );
      expect(chrome.following, isFalse);
      chrome.onLocate!();
      await tester.pump();

      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .following,
        isTrue,
      );
      // Back on the rider right away, without waiting for the next fix.
      expect(moves(h), hasLength(2));
      expect(moves(h).last.arguments.first, const LatLng(48.1, 11.2));

      await settleCamera(tester, h);
      await emitSnapshot(
        tester,
        h,
        _snapshot(lastPosition: const LatLng(48.2, 11.3)),
      );

      expect(moves(h), hasLength(3));
      expect(moves(h).last.arguments.first, const LatLng(48.2, 11.3));
      await unmountApp(tester);
    });

    testWidgets('heading up turns the map with the rider', (tester) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const {'recording.follow': 'headingUp'},
      );
      await tester.pump();

      // Walking pace: no course worth turning the map by, so the move leaves
      // the map pointing where it already pointed.
      await emitSnapshot(tester, h, _snapshot(headingDeg: 90, speedMps: 0.4));
      expect(moves(h).single.arguments[2], isNull);
      await settleCamera(tester, h);

      await emitSnapshot(
        tester,
        h,
        _snapshot(headingDeg: 90, lastPosition: const LatLng(48.2, 11.3)),
      );

      expect(moves(h).last.arguments[2], 90);
      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .headingUp,
        isTrue,
      );
      await unmountApp(tester);
    });

    testWidgets('a follow move is given a fix interval to glide over', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot());

      expect(moves(h).single.arguments[3], followCameraDuration);
      expect(followCameraDuration, const Duration(milliseconds: 1000));
      await unmountApp(tester);
    });

    testWidgets('a heading that only jitters leaves the map where it is', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const {'recording.follow': 'headingUp'},
      );
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(headingDeg: 40));
      expect(moves(h).last.arguments[2], 40);
      await settleCamera(tester, h);

      // Four degrees of GPS breathing: the smoothed heading moves by two,
      // and the camera is asked for the bearing it already has.
      await emitSnapshot(
        tester,
        h,
        _snapshot(headingDeg: 44, lastPosition: const LatLng(48.2, 11.3)),
      );

      expect(moves(h).last.arguments[2], 40);
      await unmountApp(tester);
    });

    testWidgets('a real turn does move the map', (tester) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const {'recording.follow': 'headingUp'},
      );
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(headingDeg: 40));
      expect(moves(h).last.arguments[2], 40);
      await settleCamera(tester, h);

      // Forty degrees of course, half of it smoothed away, still well past
      // the deadband.
      await emitSnapshot(
        tester,
        h,
        _snapshot(headingDeg: 80, lastPosition: const LatLng(48.2, 11.3)),
      );

      expect(moves(h).last.arguments[2], 60);
      await unmountApp(tester);
    });

    testWidgets('a rider at a standstill keeps the bearing they had', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const {'recording.follow': 'headingUp'},
      );
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(headingDeg: 40));
      expect(moves(h).last.arguments[2], 40);
      await settleCamera(tester, h);

      // Rolling to a stop: the course is noise now, so the map holds still.
      await emitSnapshot(
        tester,
        h,
        _snapshot(
          headingDeg: 200,
          speedMps: 1.0,
          lastPosition: const LatLng(48.2, 11.3),
        ),
      );

      expect(moves(h).last.arguments[2], 40);
      await unmountApp(tester);
    });

    testWidgets('north up asks for north on every move', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(headingDeg: 90));

      expect(moves(h).single.arguments[2], 0);
      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .headingUp,
        isFalse,
      );
      await unmountApp(tester);
    });

    testWidgets('the compass swaps the follow style and keeps it', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot(headingDeg: 90));
      await settleCamera(tester, h);

      Future<void> tapCompass() async {
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .onCompass!();
        await tester.pump();
        await settleAsync(tester);
      }

      await tapCompass();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recording.follow'), 'headingUp');
      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .headingUp,
        isTrue,
      );

      // And back again, which straightens the map and forgets the choice
      // rather than storing the default.
      await tapCompass();

      expect(prefs.getString('recording.follow'), isNull);
      expect(moves(h).last.arguments[2], 0);
      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .headingUp,
        isFalse,
      );
      await unmountApp(tester);
    });

    testWidgets('the locate button only re-arms following', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot(headingDeg: 90));
      await settleCamera(tester, h);

      tester
          .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
          .onLocate!();
      await tester.pump();
      await settleAsync(tester);

      // The follow style is the compass button's business, not this one's.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recording.follow'), isNull);
      final chrome = tester.widget<MapChromeInsets>(
        find.byType(MapChromeInsets).first,
      );
      expect(chrome.headingUp, isFalse);
      expect(chrome.following, isTrue);
      await unmountApp(tester);
    });

    testWidgets('the needle follows the camera', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .bearingDeg,
        0,
      );

      h.map.bearing = 40;
      await settleCamera(tester, h);

      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .bearingDeg,
        40,
      );
      await unmountApp(tester);
    });

    testWidgets('turning the map by hand stops the following', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      await settleCamera(tester, h);

      // Two fingers on the map, let go forty degrees off north.
      h.map.bearing = 40;
      await settleCamera(tester, h);

      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .following,
        isFalse,
      );
      await unmountApp(tester);
    });

    testWidgets('a ride that ends leaves the map pointing north', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const {'recording.follow': 'headingUp'},
      );
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot(headingDeg: 90));
      await settleCamera(tester, h);
      expect(moves(h).last.arguments[2], 90);

      await emitSnapshot(tester, h, _snapshot(status: RecordingStatus.idle));

      expect(moves(h).last.arguments[2], 0);
      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .following,
        isFalse,
      );
      await unmountApp(tester);
    });

    testWidgets('an idle map never follows, and says so', (tester) async {
      await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();

      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .following,
        isFalse,
      );
      await unmountApp(tester);
    });
  });

  group('the puck on the guided route', () {
    /// A match on the route 5 m from the fix, heading due east.
    const onRoute = NavigationProgress(
      snapped: LatLng(48.1001, 11.2001),
      routeBearingDeg: 90,
      distanceFromRouteM: 5,
    );

    /// Every camera move the screen asked for, in order.
    List<MapCall> moves(RecordingHarness h) =>
        h.map.calls.where((c) => c.method == 'moveTo').toList();

    /// Every puck the screen drew, in order.
    List<MapCall> pucks(RecordingHarness h) =>
        h.map.calls.where((c) => c.method == 'setPosition').toList();

    testWidgets('a rider on the route is drawn on it, facing along it', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const {'recording.follow': 'headingUp'},
        extraOverrides: [
          navigationControllerProvider.overrideWithValue(onRoute),
        ],
      );
      await tester.pump();

      // A course forty degrees off the road, which is what a GNSS course does
      // between two buildings; the road wins.
      await emitSnapshot(tester, h, _snapshot(headingDeg: 50));

      expect(pucks(h).last.arguments[0], onRoute.snapped);
      expect(pucks(h).last.arguments[1], 90);
      expect(pucks(h).last.arguments[2], 6, reason: 'the real ground speed');
      expect(moves(h).last.arguments[0], onRoute.snapped);
      expect(moves(h).last.arguments[2], 90);

      await unmountApp(tester);
    });

    testWidgets('a rider too far from the route keeps the raw fix', (
      tester,
    ) async {
      const wideOfIt = NavigationProgress(
        snapped: LatLng(48.1001, 11.2001),
        routeBearingDeg: 90,
        distanceFromRouteM: 40,
      );
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const {'recording.follow': 'headingUp'},
        extraOverrides: [
          navigationControllerProvider.overrideWithValue(wideOfIt),
        ],
      );
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(headingDeg: 50));

      expect(pucks(h).last.arguments[0], const LatLng(48.1, 11.2));
      expect(pucks(h).last.arguments[1], 50);
      expect(moves(h).last.arguments[2], 50);

      await unmountApp(tester);
    });

    testWidgets('a rider called off route keeps the raw fix too', (
      tester,
    ) async {
      const strayed = NavigationProgress(
        snapped: LatLng(48.1001, 11.2001),
        routeBearingDeg: 90,
        distanceFromRouteM: 5,
        offRoute: true,
      );
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const {'recording.follow': 'headingUp'},
        extraOverrides: [
          navigationControllerProvider.overrideWithValue(strayed),
        ],
      );
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(headingDeg: 50));

      expect(pucks(h).last.arguments[0], const LatLng(48.1, 11.2));
      expect(pucks(h).last.arguments[1], 50);

      await unmountApp(tester);
    });
  });

  group('the turn banner', () {
    const progress = NavigationProgress(
      next: TurnHint(pointIndex: 10, kind: TurnKind.left),
      distanceToNextM: 200,
    );

    testWidgets('rides with a guided route and pushes the controls down', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        extraOverrides: [
          navigationControllerProvider.overrideWithValue(progress),
        ],
      );
      await tester.pump();
      expect(find.byType(TurnBanner), findsNothing);

      await emitSnapshot(tester, h, _snapshot());

      expect(find.byType(TurnBanner), findsOneWidget);
      expect(find.text('200 m'), findsOneWidget);
      expect(find.text('Turn left'), findsOneWidget);
      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .controlsTop,
        turnBannerHeight + 24,
      );

      await unmountApp(tester);
    });

    testWidgets('stays away when nothing is being guided', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot());

      expect(find.byType(TurnBanner), findsNothing);
      expect(
        tester
            .widget<MapChromeInsets>(find.byType(MapChromeInsets).first)
            .controlsTop,
        isNull,
      );

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
