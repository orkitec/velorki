import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/recording/application/ride_finish_request.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/features/recording/domain/ride_naming.dart';
import 'package:velorki/core/geo/ride_stats.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/map/presentation/puck_ownership.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/presentation/navigation_toggles.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/recording/data/recording_settings.dart';
import 'package:velorki/features/recording/domain/gps_precision.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/ride_cue_sheet.dart';
import 'package:velorki/features/recording/presentation/ride_profile_view.dart';
import 'package:velorki/features/library/presentation/library_screen.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/recording/presentation/follow_route_picker.dart';
import 'package:velorki/features/recording/presentation/ride_detail_screen.dart';
import 'package:velorki/features/recording/presentation/rides_list.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki/features/shared/application/nav_bar_docking.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
import '../search/support/gazetteer_fixture.dart';
import '../planner/support/fakes.dart' show MapCall, syntheticRoute;
import 'support/pump.dart';

RecordingSnapshot _snapshot({
  RecordingStatus status = RecordingStatus.active,
  bool autoPaused = false,
  double distanceM = 12345,
  List<LatLng> newPoints = const <LatLng>[],
  LatLng lastPosition = const LatLng(48.1, 11.2),
  double? headingDeg,
  double speedMps = 6,
  int? heartRateBpm,
  int? cadenceRpm,
  int? powerW,
  int? avgHeartRateBpm,
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
  heartRateBpm: heartRateBpm,
  cadenceRpm: cadenceRpm,
  powerW: powerW,
  avgHeartRateBpm: avgHeartRateBpm,
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

/// The recording a stopped ride leaves behind for the save sheet.
RecordingState _recording() => RecordingState(
  rideId: 'ride-1',
  startedAt: DateTime.utc(2026, 9, 12, 10),
  status: RecordingStatus.active,
);

/// A journal that starts and ends in the same spot: a loop, with no gazetteer
/// to name the ground it ran over.
List<TrackPoint> _journalPoints() => <TrackPoint>[
  TrackPoint(
    const LatLng(32.6669, -16.9241),
    time: DateTime.utc(2026, 9, 12, 10),
  ),
  TrackPoint(
    const LatLng(32.6687, -16.9241),
    time: DateTime.utc(2026, 9, 12, 10, 30),
  ),
  TrackPoint(
    const LatLng(32.6669, -16.9241),
    time: DateTime.utc(2026, 9, 12, 11),
  ),
];

/// The name the sheet offers for [_recording] over [_journalPoints]: a loop,
/// named after the part of the day the ride started in locally.
String get _defaultName => defaultRideName(
  l10n,
  startedAt: DateTime.utc(2026, 9, 12, 10).toLocal(),
  isLoop: true,
);

/// Lets the journal read and the place lookup behind the sheet finish, then
/// settles the sheet's animation.
///
/// Naming a ride is a chain of real file system work — the journal, then the
/// gazetteer — and [WidgetTester.pumpAndSettle] drives only the frame
/// scheduler, so each link needs its own turn of the real event loop.
Future<void> settleSheet(WidgetTester tester) async {
  // The sheet opens after real work — pausing the recorder, reading the
  // journal — that takes longer on a loaded CI runner than on a laptop, so
  // the wait is for the sheet itself rather than a fixed number of rounds,
  // and a sheet that is not coming (a test about staying put) costs a second.
  for (var i = 0; i < 50; i++) {
    await settleAsync(tester);
    if (i >= 5 && find.byType(SaveRideSheet).evaluate().isNotEmpty) break;
  }
  await tester.pumpAndSettle();
}

/// Writes [_journalPoints] as the journal of `ride-1` in [harness].
///
/// Through [WidgetTester.runAsync]: a test body runs in fake time, where a
/// real file write never completes.
Future<void> writeJournal(
  WidgetTester tester,
  RecordingHarness harness, [
  List<TrackPoint>? points,
]) => tester.runAsync(
  () =>
      RecordingStore(harness.directory)
          .writeJournal('ride-1', points ?? _journalPoints()),
);

/// What the screen last told the shell's control column, which is what the
/// column's buttons call and show.
MapChromeData chromeOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(RecordingScreen)))
        .read(activeMapChromeProvider)!;

/// Where the shell's control column is on its glide right now.
double controlsTopOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(RecordingScreen)))
        .read(mapControlsTopProvider)
        .animation
        .value;

void main() {
  testWidgets('the idle tab offers a start button and the route chooser', (
    tester,
  ) async {
    await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    expect(find.text(l10n.recordingIdleTitle), findsOneWidget);
    expect(find.text(l10n.recordingStart), findsOneWidget);
    expect(find.text(l10n.recordingFollowRoute), findsOneWidget);
    expect(find.text(l10n.recordingFollowNone), findsOneWidget);
    expect(find.byType(FollowRouteField), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('the route chooser opens a picker over the bar, on the root '
      'navigator, and a tap there sets the route', (tester) async {
    final h = RecordingHarness();
    final saved =
        await RouteRepository(
          h.planner.db.routesDao,
          clock: () => DateTime.utc(2026, 9, 12, 10),
        ).savePlannedRoute(
          name: 'Isar loop',
          route: syntheticRoute(),
          waypoints: const [
            Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
            Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
          ],
          options: const RoutingOptions(),
        );
    await pumpRecordingApp(tester, harness: h);
    await tester.pumpAndSettle();
    expect(find.byType(FollowRoutePicker), findsNothing);

    await tester.tap(find.byType(FollowRouteField));
    await tester.pumpAndSettle();

    // On the root navigator, so it paints over the floating bar.
    final picker = find.byType(FollowRoutePicker);
    expect(picker, findsOneWidget);
    final pickerContext = tester.element(picker);
    expect(
      Navigator.of(pickerContext),
      same(Navigator.of(pickerContext, rootNavigator: true)),
    );
    expect(
      tester.getRect(picker).bottom,
      greaterThan(tester.getRect(find.byType(FloatingNavigationBar)).top),
    );
    // Titled, "No route" first and ticked, the library's rows after it.
    expect(
      find.descendant(
        of: picker,
        matching: find.text(l10n.recordingFollowRoute),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: picker,
        matching: find.text(l10n.recordingFollowNone),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.byType(RouteRow)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: picker,
        matching: find.text(
          l10n.libraryRouteSubtitle(
            testDate(DateTime.utc(2026, 9, 12, 10).toLocal()),
            testDistance(10000),
            testHeight(120),
          ),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: picker, matching: find.text('Isar loop')),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordingScreen)),
    );
    expect(
      container.read(recordingControllerProvider).followedRouteId,
      saved.id,
    );
    expect(find.byType(FollowRoutePicker), findsNothing);
    // The row names the choice, with its distance.
    expect(find.textContaining('Isar loop'), findsOneWidget);
    expect(find.textContaining(testDistance(10000)), findsOneWidget);

    // Opened again, the route is the one ticked; "No route" clears it.
    await tester.tap(find.byType(FollowRouteField));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RouteRow>(
            find.descendant(of: picker, matching: find.byType(RouteRow)),
          )
          .selected,
      isTrue,
    );
    await tester.tap(
      find.descendant(
        of: picker,
        matching: find.text(l10n.recordingFollowNone),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(recordingControllerProvider).followedRouteId, isNull);
    expect(find.text(l10n.recordingFollowNone), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('the planned route is drawn while no saved route is followed', (
    tester,
  ) async {
    final h = RecordingHarness();
    await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
    await tester.pump();
    expect(find.text(l10n.recordingFollowNone), findsOneWidget);

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
    expect(find.text(l10n.recordingFollowPlan), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a whole new route to the destination takes the plan\'s place', (
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
            key: 'reroute:1:2',
            line: detour,
            turns: <TurnHint>[],
            replacesPlan: true,
          ),
        );
    await tester.pumpAndSettle();

    expect(h.map.lines[followedRouteLineId], detour);
    expect(h.map.lines[detourRouteLineId], isNull);

    await unmountApp(tester);
  });

  testWidgets('a way back onto the route is a branch beside the plan', (
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
    final plan = h.map.lines[followedRouteLineId];
    expect(plan, isNotNull);

    const branch = <LatLng>[LatLng(48.05, 11.2), LatLng(48.08, 11.25)];
    container
        .read(detourRouteProvider.notifier)
        .replace(
          const GuidedRoute(
            key: 'detour:1:2',
            line: <LatLng>[...branch, LatLng(48.1, 11.1)],
            turns: <TurnHint>[],
            branch: branch,
            rejoinAlongM: 900,
          ),
        );
    await tester.pumpAndSettle();

    // The plan stays where it was, muted, and the way back is drawn on its
    // own beside it: a rider has to see both to know what is being asked.
    expect(h.map.lines[followedRouteLineId], plan);
    expect(h.map.styles[followedRouteLineId], RouteLineStyle.alternative);
    expect(h.map.lines[detourRouteLineId], branch);
    expect(h.map.styles[detourRouteLineId], RouteLineStyle.preview);

    // Back on the plan, the branch goes and the plan reads as it did.
    container.read(detourRouteProvider.notifier).replace(null);
    await tester.pumpAndSettle();

    expect(h.map.lines[detourRouteLineId], isNull);
    expect(h.map.styles[followedRouteLineId], RouteLineStyle.preview);

    await unmountApp(tester);
  });

  testWidgets('the idle tab lists no rides, on a small screen either', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await RideRepository(harness.planner.db.ridesDao).save(_ride());
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: harness,
      // The smallest phone the app is drawn for: the sheet still holds the
      // start button and the options, and scrolls for the rest.
      surfaceSize: const Size(360, 640),
    );
    await tester.pumpAndSettle();

    // The rides belong to the Library tab; the record tab is the map, the
    // start button and the options.
    expect(find.byType(RidesList), findsNothing);
    expect(find.text('Ride 12 Sept 2026'), findsNothing);
    expect(find.text(l10n.recordingNoRides), findsNothing);
    expect(find.text(l10n.recordingStart), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('starting asks for the location and then starts the recorder', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await tester.tap(find.text(l10n.recordingStart));
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

    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();

    expect(h.service.calls, isEmpty);
    expect(find.text(l10n.recordingLocationDenied), findsOneWidget);
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

    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();

    expect(find.text(l10n.recordingBatteryTitle), findsOneWidget);
    await tester.tap(find.text(l10n.recordingBatteryAllow));
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

    expect(
      find.text(l10n.recordingStatusRecording.toUpperCase()),
      findsOneWidget,
    );
    expect(find.byType(NavigationBar), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('before a ride the sheet docks in the navigation bar; during '
      'one it only drops to its handle', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();
    DockingSheetShell shell() =>
        tester.widget<DockingSheetShell>(find.byType(DockingSheetShell));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordingScreen)),
    );
    expect(shell().docks, isTrue);
    expect(shell().docked, 0);

    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 1500),
    );
    await tester.pumpAndSettle();
    expect(shell().docked, 1);
    expect(container.read(navBarDockingProvider), {recordingRoute});
    expectNoClippedText(tester);

    // A ride starting under the docked sheet (from the watch, say): the bar
    // goes, the live sheet has nothing to dock into, and the bar is told so
    // it comes back round.
    await emitSnapshot(
      tester,
      h,
      _snapshot(newPoints: const [LatLng(48.0, 11.0), LatLng(48.1, 11.2)]),
    );
    await tester.pumpAndSettle();
    expect(shell().docks, isFalse);
    expect(shell().docked, 0);
    expect(container.read(navBarDockingProvider), isEmpty);

    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 1500),
    );
    await tester.pumpAndSettle();
    expect(shell().docked, 0);
    expect(container.read(navBarDockingProvider), isEmpty);

    await unmountApp(tester);
  });

  testWidgets('the idle sheet rests where the Plan sheet rests', (
    tester,
  ) async {
    await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();
    final screenHeight = MediaQuery.sizeOf(
      tester.element(find.byType(RecordingScreen)),
    ).height;
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(sheet.initialChildSize, sheetRestingExtent(screenHeight));
    expect(sheet.snapSizes, [sheetRestingExtent(screenHeight)]);
    // The start button is still in view at that height.
    expect(find.text(l10n.recordingStart), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a ride recording while Plan is up keeps the puck on the shared '
      'map but leaves the camera alone, then re-centres once on return', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordingScreen)),
    );
    List<MapCall> calls(String method) =>
        h.map.calls.where((c) => c.method == method).toList();

    await emitSnapshot(
      tester,
      h,
      _snapshot(newPoints: const [LatLng(48.0, 11.0), LatLng(48.1, 11.2)]),
    );
    expect(calls('moveTo'), hasLength(1));
    expect(calls('setTrackLine'), isNotEmpty);
    expect(container.read(recorderOwnsPuckProvider), isTrue);
    h.map.onCameraIdle?.call();
    await tester.pump();

    // Plan comes up: the track goes, the camera idle handler with it.
    container.read(activeTabProvider.notifier).show(plannerRoute);
    await tester.pump();
    expect(calls('setTrackLine').last.arguments.single, isEmpty);
    expect(h.map.onCameraIdle, isNull);
    final movesBefore = calls('moveTo').length;
    final tracksBefore = calls('setTrackLine').length;
    final pucksBefore = calls('setPosition').length;

    // A fix while the rider looks at the plan moves the puck, and nothing
    // else: the map's own fix is muted while the recorder owns the puck,
    // and a puck that froze would be a lie.
    await emitSnapshot(
      tester,
      h,
      _snapshot(
        newPoints: const [LatLng(48.2, 11.3)],
        lastPosition: const LatLng(48.2, 11.3),
      ),
    );
    expect(calls('setPosition'), hasLength(pucksBefore + 1));
    expect(calls('setPosition').last.arguments.first, const LatLng(48.2, 11.3));
    expect(calls('moveTo'), hasLength(movesBefore));
    expect(calls('setTrackLine'), hasLength(tracksBefore));

    // Back on Record: the track is drawn whole and the camera comes back
    // to the rider once, without waiting for the next fix.
    container.read(activeTabProvider.notifier).show(recordingRoute);
    await tester.pump();
    expect(calls('setTrackLine').last.arguments.single, hasLength(3));
    expect(calls('moveTo'), hasLength(movesBefore + 1));
    expect(calls('moveTo').last.arguments.first, const LatLng(48.2, 11.3));
    expect(h.map.onCameraIdle, isNotNull);
    await tester.pump();
    expect(calls('moveTo'), hasLength(movesBefore + 1));

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

    expect(
      find.text(l10n.recordingStatusRecording.toUpperCase()),
      findsOneWidget,
    );
    expect(find.text(testDistance(12345)), findsOneWidget);
    expect(find.text('42:07'), findsOneWidget);
    expect(find.text('40:00'), findsOneWidget);
    expect(find.text(testHeight(210)), findsOneWidget);
    expect(find.byTooltip(l10n.recordingPause), findsOneWidget);
    expect(find.byTooltip(l10n.recordingFinish), findsOneWidget);
    // No sensor is paired, so the third row is not there at all.
    expect(find.text(l10n.statHeartRate.toUpperCase()), findsNothing);

    final track = h.map.calls.where((c) => c.method == 'setTrackLine').last;
    expect(track.arguments.first, hasLength(2));
    expect(h.map.calls.where((c) => c.method == 'setPosition'), isNotEmpty);

    await unmountApp(tester);
  });

  testWidgets('the sensor row appears once something reports', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(
      tester,
      h,
      _snapshot(heartRateBpm: 142, cadenceRpm: 0, powerW: 210),
    );

    expect(find.text(l10n.statHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statCadence.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statPower.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.unitBpm('142')), findsOneWidget);
    expect(find.text(l10n.unitRpm('0')), findsOneWidget);
    expect(find.text(l10n.unitWatts('210')), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a sensor that falls silent keeps its tile, dimmed and marked, '
      'with the last value', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(tester, h, _snapshot(heartRateBpm: 142));
    expect(find.byIcon(Icons.link_off), findsNothing);

    // The watch went out of range: the reading is gone from the snapshot.
    await emitSnapshot(tester, h, _snapshot());
    expect(find.text(l10n.statHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.unitBpm('142')), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsOneWidget);

    // Paused, the sensor rests on purpose: nothing to mark.
    await emitSnapshot(tester, h, _snapshot(status: RecordingStatus.paused));
    expect(find.text(l10n.unitBpm('142')), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('the average heart rate rides along under the tile', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(
      tester,
      h,
      _snapshot(heartRateBpm: 142, avgHeartRateBpm: 138),
    );

    expect(
      find.text('${l10n.statAvgHeartRate} ${l10n.unitBpm('138')}'),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('a swipe on the figures brings the elevation page, and back', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();
    await emitSnapshot(tester, h, _snapshot());
    expect(find.byType(RideProfileView), findsNothing);

    await tester.fling(
      find.text(l10n.statDistance.toUpperCase()),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();

    // No route is followed, so the page says what it would show; the
    // figures are gone, and a fresh snapshot keeps the page.
    expect(find.byType(RideProfileView), findsOneWidget);
    expect(find.text(l10n.recordingProfileNoRoute), findsOneWidget);
    expect(find.text(l10n.statDistance.toUpperCase()), findsNothing);
    await emitSnapshot(tester, h, _snapshot(distanceM: 13000));
    expect(find.byType(RideProfileView), findsOneWidget);

    await tester.fling(
      find.text(l10n.recordingProfileNoRoute),
      const Offset(300, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.byType(RideProfileView), findsNothing);
    expect(find.text(l10n.statDistance.toUpperCase()), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a second swipe brings the cue sheet: the turns ahead with '
      'their distance', (tester) async {
    final route = GuidedRoute(
      key: 'saved:r',
      line: const <LatLng>[
        LatLng(48.1, 11.2),
        LatLng(48.101, 11.2),
        LatLng(48.102, 11.2),
      ],
      turns: const <TurnHint>[
        TurnHint(pointIndex: 1, kind: TurnKind.left, note: 'Left at the mill'),
      ],
    );
    final h = await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      extraOverrides: [
        activeGuidedRouteProvider.overrideWithValue(route),
        navigationControllerProvider.overrideWithValue(
          const NavigationProgress(alongM: 0, remainingM: 222),
        ),
      ],
    );
    await tester.pump();
    await emitSnapshot(tester, h, _snapshot());

    // On a route, the figures page also says what is left and when it ends.
    expect(find.text(l10n.statRemaining.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statArrival.toUpperCase()), findsOneWidget);
    expect(find.text(testDistance(222)), findsOneWidget);

    await tester.fling(
      find.text(l10n.statDistance.toUpperCase()),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();
    // The profile page has no elevations to draw for this route; its text
    // is what there is to swipe on.
    await tester.fling(
      find.text(l10n.recordingProfileNoRoute),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.recordingCuesTitle.toUpperCase()), findsOneWidget);
    expect(find.text('Left at the mill'), findsOneWidget);
    expect(find.text(l10n.navArrive), findsOneWidget);
    // 111 m to the mill; the end shows the same 220 m the ascent tile
    // happens to read, so the cue sheet's own rows are what is counted.
    expect(find.text('110 m'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RideCueSheet),
        matching: find.text('220 m'),
      ),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('the sensor row shows only the figures that are reported', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    // A watch and nothing else: one tile, no dashes for the rest.
    await emitSnapshot(tester, h, _snapshot(heartRateBpm: 142));

    expect(find.text(l10n.statHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statCadence.toUpperCase()), findsNothing);
    expect(find.text(l10n.statPower.toUpperCase()), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('pause and resume reach the recorder', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(tester, h, _snapshot());
    await tester.tap(find.byTooltip(l10n.recordingPause));
    await tester.pump();
    expect(h.service.calls, contains('pause'));

    await emitSnapshot(tester, h, _snapshot(status: RecordingStatus.paused));
    expect(find.text(l10n.recordingStatusPaused.toUpperCase()), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.recordingResume));
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

    expect(
      find.text(l10n.recordingStatusAutoPaused.toUpperCase()),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('finishing an empty ride says nothing was recorded', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await emitSnapshot(tester, h, _snapshot());
    await tester.tap(find.byTooltip(l10n.recordingFinish));
    await settleSheet(tester);

    expect(h.service.calls, <String>['pause', 'halt']);
    expect(find.byType(SaveRideSheet), findsNothing);
    expect(find.text(l10n.recordingNothingRecorded), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a ride with nothing in its journal is not worth naming', (
    tester,
  ) async {
    final h = RecordingHarness()..service.haltedRecording = _recording();
    await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
    await tester.pump();

    await emitSnapshot(tester, h, _snapshot());
    await tester.tap(find.byTooltip(l10n.recordingFinish));
    await settleSheet(tester);

    expect(find.byType(SaveRideSheet), findsNothing);
    expect(h.service.calls, <String>[
      'pause',
      'halt',
      'finishInterrupted(ride-1)',
    ]);
    expect(find.text(l10n.recordingNothingRecorded), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('saving a ride opens its card on the Library tab', (
    tester,
  ) async {
    final harness = RecordingHarness()
      ..service.finishedRide = _ride()
      ..service.haltedRecording = _recording();
    await writeJournal(tester, harness);
    await RideRepository(harness.planner.db.ridesDao).save(_ride());
    await pumpRecordingApp(tester, harness: harness);
    await tester.pump();

    await emitSnapshot(tester, harness, _snapshot());
    await tester.tap(find.byTooltip(l10n.recordingFinish));
    await settleSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
    await settleSheet(tester);

    expect(find.byType(RideDetailScreen), findsOneWidget);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('Ride 12 Sept 2026'), findsWidgets);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    expect(container.read(activeTabProvider), libraryRoute);
    // The ride went on the shared map, above the card.
    expect(harness.map.trackSegments, isNotEmpty);
    await unmountApp(tester);
  });

  testWidgets('a finish asked for from the watch opens the save sheet', (
    tester,
  ) async {
    final harness = RecordingHarness()
      ..service.finishedRide = _ride()
      ..service.haltedRecording = _recording();
    await writeJournal(tester, harness);
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: harness,
    );
    await tester.pump();
    await emitSnapshot(tester, harness, _snapshot());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordingScreen)),
    );

    // What the watch's Finish leaves behind: the recorder already put down,
    // and the ride waiting to be named the next time the phone is looked at.
    container.read(rideFinishRequestProvider.notifier).raise();
    await settleSheet(tester);

    expect(find.byType(SaveRideSheet), findsOneWidget);
    expect(container.read(rideFinishRequestProvider), isFalse);

    // Finish tapped again on the watch while the sheet is up: still one.
    container.read(rideFinishRequestProvider.notifier).raise();
    await settleSheet(tester);
    expect(find.byType(SaveRideSheet), findsOneWidget);
    expect(container.read(rideFinishRequestProvider), isFalse);
    await unmountApp(tester);
  });

  testWidgets('a late snapshot after finishing does not revive the ride', (
    tester,
  ) async {
    final harness = RecordingHarness()
      ..service.finishedRide = _ride()
      ..service.haltedRecording = _recording();
    await writeJournal(tester, harness);
    await RideRepository(harness.planner.db.ridesDao).save(_ride());
    await pumpRecordingApp(tester, harness: harness);
    await tester.pump();

    await emitSnapshot(tester, harness, _snapshot());
    await tester.tap(find.byTooltip(l10n.recordingFinish));
    await settleSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
    await settleSheet(tester);
    expect(find.byType(RideDetailScreen), findsOneWidget);

    // The foreground isolate flushes one last time after the stop; the
    // Record tab must stay ready for the next ride, not go live again.
    await emitSnapshot(tester, harness, _snapshot());
    await tester.tap(find.text(l10n.tabRecord));
    await tester.pumpAndSettle();

    expect(find.text(l10n.recordingIdleTitle), findsOneWidget);
    expect(
      find.text(l10n.recordingStatusRecording.toUpperCase()),
      findsNothing,
    );
    await unmountApp(tester);
  });

  testWidgets('the keep-screen-on toggle drives the wake lock', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    await tester.tap(find.text(l10n.recordingKeepScreenOn));
    await tester.pumpAndSettle();
    expect(h.screenWake.enabled, isTrue);

    await tester.tap(find.text(l10n.recordingKeepScreenOn));
    await tester.pumpAndSettle();
    expect(h.screenWake.enabled, isFalse);

    await unmountApp(tester);
  });

  testWidgets('the navigation switches sit below the fold on both sheets', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();

    expect(find.byType(NavigationToggles), findsOneWidget);
    // The same rows as Settings > Navigation, after "Keep screen on".
    final keep = tester.getTopLeft(find.text(l10n.recordingKeepScreenOn));
    final voice = tester.getTopLeft(find.text(l10n.settingsVoiceDirections));
    expect(voice.dy, greaterThan(keep.dy));

    await tester.tap(
      find.text(l10n.settingsVoiceDirections),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordingScreen)),
    );
    expect(container.read(navigationSettingsProvider).voice, isFalse);

    // The live sheet carries the same rows, below the figures.
    await emitSnapshot(tester, h, _snapshot());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationToggles), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.ancestor(
              of: find.text(l10n.settingsVoiceDirections),
              matching: find.byType(SwitchListTile),
            ),
          )
          .value,
      isFalse,
    );

    await unmountApp(tester);
  });

  testWidgets('the idle sheet scrolls its content at its resting height, and '
      'moves only by its handle', (tester) async {
    // A phone: on the tall test surface the idle list would fit its sheet
    // whole, with nothing to scroll.
    tester.view.physicalSize = const Size(1125, 2001);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      surfaceSize: const Size(375, 667),
    );
    await tester.pumpAndSettle();
    DockingSheetShell shell() =>
        tester.widget<DockingSheetShell>(find.byType(DockingSheetShell));
    final resting = shell().extent;
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );

    // The switches sit below the fold, not even built yet; a drag on the
    // list scrolls the list up to them while the sheet stays at rest.
    final toggles = find.byType(NavigationToggles);
    final list = tester.state<ScrollableState>(
      find
          .ancestor(
            of: find.text(l10n.recordingStart),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(list.position.pixels, 0);
    expect(toggles, findsNothing);
    await tester.drag(find.text(l10n.recordingStart), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(list.position.pixels, greaterThan(100));
    expect(toggles, findsOneWidget);
    expect(shell().extent, closeTo(resting, 0.001));

    // The handle takes the sheet to its top, and from there down again,
    // all the way into the bar.
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(shell().extent, closeTo(sheet.maxChildSize, 0.001));
    // At the top the list still scrolls on its own.
    await tester.drag(find.byType(NavigationToggles), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(shell().extent, closeTo(sheet.maxChildSize, 0.001));
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 650),
    );
    await tester.pumpAndSettle();
    expect(shell().extent, closeTo(sheet.minChildSize, 0.001));
    expect(shell().docked, 1);

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
    expect(find.text(l10n.recordingRecoveryTitle), findsNothing);
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

      expect(find.text(l10n.recordingRecoveryTitle), findsOneWidget);
      expect(find.textContaining(testDistance(12345)), findsOneWidget);
      expect(
        find.textContaining(testDuration(const Duration(minutes: 42))),
        findsOneWidget,
      );
      await unmountApp(tester);
    });

    testWidgets('Resume continues the recording', (tester) async {
      final h = harnessWith();
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, l10n.recordingResume));
      await tester.pumpAndSettle();
      await settleAsync(tester);

      expect(h.service.calls, <String>['resumeInterrupted(ride-1)']);
      await unmountApp(tester);
    });

    testWidgets('Finish goes through the save sheet', (tester) async {
      final h = harnessWith();
      await writeJournal(tester, h);
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.recordingFinish));
      await settleSheet(tester);
      expect(find.byType(SaveRideSheet), findsOneWidget);
      expect(find.text(l10n.rideSaveTitle), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
      await settleSheet(tester);

      expect(h.service.calls, <String>['finishInterrupted(ride-1)']);
      expect(h.service.savedNames, <String>[_defaultName]);
      await unmountApp(tester);
    });

    testWidgets('Discard throws it away', (tester) async {
      final h = harnessWith();
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.recordingRecoveryDiscard));
      await tester.pumpAndSettle();

      expect(h.service.calls, <String>['discardInterrupted(ride-1)']);
      await unmountApp(tester);
    });
  });

  group('the save sheet', () {
    /// A stopped ride waiting to be named, with a loop in its journal.
    ///
    /// The whole shell, not the bare screen: saving goes on to the ride's
    /// detail page, which needs the router.
    Future<RecordingHarness> pumpStopped(
      WidgetTester tester, {
      List<GazPlace> places = const <GazPlace>[],
    }) async {
      final h = RecordingHarness()
        ..service.haltedRecording = _recording()
        ..service.finishedRide = _ride();
      await writeJournal(tester, h);
      if (places.isNotEmpty) {
        buildGazetteer(h.gazetteerDirectory, 'W20_N30', places: places);
      }
      await RideRepository(h.planner.db.ridesDao).save(_ride());
      await pumpRecordingApp(tester, harness: h);
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      await tester.tap(find.byTooltip(l10n.recordingFinish));
      await settleSheet(tester);
      return h;
    }

    /// A finder inside the sheet, so the live panel behind it is not matched.
    Finder inSheet(Finder finder) =>
        find.descendant(of: find.byType(SaveRideSheet), matching: finder);

    Finder saveButton() => find.widgetWithText(FilledButton, l10n.commonSave);

    testWidgets('opens on stop with the default name selected', (tester) async {
      final h = await pumpStopped(tester);

      expect(find.byType(SaveRideSheet), findsOneWidget);
      expect(find.text(l10n.rideSaveTitle), findsOneWidget);
      expect(h.service.calls, <String>['pause']);

      final field = tester.widget<TextField>(inSheet(find.byType(TextField)));
      expect(field.controller?.text, _defaultName);
      expect(
        field.controller?.selection,
        TextSelection(baseOffset: 0, extentOffset: _defaultName.length),
        reason: 'typing replaces the suggestion',
      );
      expectNoClippedText(tester);
      await unmountApp(tester);
    });

    testWidgets('the keyboard stays down when the sheet opens', (tester) async {
      await pumpStopped(tester);

      final field = tester.widget<TextField>(inSheet(find.byType(TextField)));
      expect(
        field.focusNode?.hasFocus,
        isFalse,
        reason: 'a keyboard on open would cover the sheet and its buttons',
      );
      expect(FocusManager.instance.primaryFocus, isNot(field.focusNode));
      await unmountApp(tester);
    });

    testWidgets('a tap into the name selects all of it', (tester) async {
      await pumpStopped(tester);

      await tester.tap(inSheet(find.byType(TextField)));
      await tester.pump();

      final field = tester.widget<TextField>(inSheet(find.byType(TextField)));
      expect(field.focusNode?.hasFocus, isTrue);
      expect(
        field.controller?.selection,
        TextSelection(baseOffset: 0, extentOffset: _defaultName.length),
        reason: 'the whole proposed name is selected, so typing replaces it',
      );

      await tester.enterText(
        inSheet(find.byType(TextField)),
        'Levada do Norte',
      );
      expect(field.controller?.text, 'Levada do Norte');
      await unmountApp(tester);
    });

    testWidgets('shows what was ridden', (tester) async {
      await pumpStopped(tester);

      expect(
        inSheet(find.text(l10n.statDistance.toUpperCase())),
        findsOneWidget,
      );
      expect(inSheet(find.text(testDistance(12345))), findsOneWidget);
      expect(
        inSheet(find.text(l10n.statMovingTime.toUpperCase())),
        findsOneWidget,
      );
      expect(inSheet(find.text(l10n.statAscent.toUpperCase())), findsOneWidget);
      expect(inSheet(find.text(testHeight(210))), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('the name carries the place the gazetteer knows', (
      tester,
    ) async {
      await pumpStopped(
        tester,
        places: const <GazPlace>[
          GazPlace(1, 'Funchal', 'city', 32.6669, -16.9241, population: 105000),
        ],
      );

      final field = tester.widget<TextField>(inSheet(find.byType(TextField)));
      expect(
        field.controller?.text,
        defaultRideName(
          l10n,
          startedAt: DateTime.utc(2026, 9, 12, 10).toLocal(),
          startPlace: 'Funchal',
          endPlace: 'Funchal',
          isLoop: true,
        ),
      );
      expectNoClippedText(tester);
      await unmountApp(tester);
    });

    testWidgets('Save keeps the name the rider typed', (tester) async {
      final h = await pumpStopped(tester);

      await tester.enterText(
        inSheet(find.byType(TextField)),
        'Levada do Norte',
      );
      await tester.tap(saveButton());
      await settleSheet(tester);

      expect(find.byType(SaveRideSheet), findsNothing);
      expect(h.service.calls, <String>[
        'pause',
        'halt',
        'finishInterrupted(ride-1)',
      ]);
      expect(h.service.savedNames, <String>['Levada do Norte']);
      await unmountApp(tester);
    });

    testWidgets('a name of nothing but spaces falls back to the default', (
      tester,
    ) async {
      final h = await pumpStopped(tester);

      await tester.enterText(inSheet(find.byType(TextField)), '   ');
      await tester.tap(saveButton());
      await settleSheet(tester);

      expect(h.service.savedNames, <String>[_defaultName]);
      await unmountApp(tester);
    });

    testWidgets('Discard asks once and then throws the ride away', (
      tester,
    ) async {
      final h = await pumpStopped(tester);

      await tester.tap(find.widgetWithText(TextButton, l10n.rideSaveDiscard));
      await tester.pumpAndSettle();
      expect(find.text(l10n.rideSaveDiscardTitle), findsOneWidget);
      expect(find.text(l10n.rideSaveDiscardBody), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, l10n.rideSaveDiscard));
      await settleSheet(tester);

      expect(find.byType(SaveRideSheet), findsNothing);
      expect(h.service.calls, <String>[
        'pause',
        'halt',
        'discardInterrupted(ride-1)',
      ]);
      expect(h.service.savedNames, isEmpty);
      await unmountApp(tester);
    });

    testWidgets('cancelling the question leaves the sheet standing', (
      tester,
    ) async {
      final h = await pumpStopped(tester);

      await tester.tap(find.widgetWithText(TextButton, l10n.rideSaveDiscard));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.rideSaveDiscardTitle), findsNothing);
      expect(find.byType(SaveRideSheet), findsOneWidget);
      expect(h.service.calls, <String>['pause']);
      await unmountApp(tester);
    });

    testWidgets('a tap outside does not leave the ride half-finished', (
      tester,
    ) async {
      final h = await pumpStopped(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(SaveRideSheet), findsOneWidget);
      expect(h.service.calls, <String>['pause']);
      await unmountApp(tester);
    });

    testWidgets('Continue resumes the recording with the same ride', (
      tester,
    ) async {
      final h = await pumpStopped(tester);

      await tester.tap(
        find.widgetWithText(OutlinedButton, l10n.rideSaveContinue),
      );
      await settleSheet(tester);

      expect(find.byType(SaveRideSheet), findsNothing);
      expect(h.service.calls, <String>[
        'pause',
        'resume',
      ], reason: 'nothing is written and nothing is thrown away');
      expect(h.service.savedNames, isEmpty);
      // The live panel is still there, on the ride that was never finished.
      expect(
        find.text(l10n.recordingStatusRecording.toUpperCase()),
        findsOneWidget,
      );
      await unmountApp(tester);
    });

    testWidgets('back acts like Continue', (tester) async {
      final h = await pumpStopped(tester);

      await tester.binding.handlePopRoute();
      await settleSheet(tester);

      expect(find.byType(SaveRideSheet), findsNothing);
      expect(h.service.calls, <String>['pause', 'resume']);
      expect(h.service.savedNames, isEmpty);
      await unmountApp(tester);
    });

    testWidgets('a ride the rider paused first is not resumed by Continue', (
      tester,
    ) async {
      final h = RecordingHarness()
        ..service.haltedRecording = _recording()
        ..service.finishedRide = _ride();
      await writeJournal(tester, h);
      await RideRepository(h.planner.db.ridesDao).save(_ride());
      await pumpRecordingApp(tester, harness: h);
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot(status: RecordingStatus.paused));
      await tester.tap(find.byTooltip(l10n.recordingFinish));
      await settleSheet(tester);

      await tester.tap(
        find.widgetWithText(OutlinedButton, l10n.rideSaveContinue),
      );
      await settleSheet(tester);

      expect(
        h.service.calls,
        isEmpty,
        reason: 'it was already paused, so there is nothing to undo',
      );
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
      final chrome = chromeOf(tester);
      expect(chrome.following, isFalse);
      chrome.onLocate!();
      await tester.pump();

      expect(chromeOf(tester).following, isTrue);
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
      expect(chromeOf(tester).headingUp, isTrue);
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
      expect(chromeOf(tester).headingUp, isFalse);
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
        chromeOf(tester).onCompass!();
        await tester.pump();
        await settleAsync(tester);
      }

      await tapCompass();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recording.follow'), 'headingUp');
      expect(chromeOf(tester).headingUp, isTrue);

      // And back again, which straightens the map and forgets the choice
      // rather than storing the default.
      await tapCompass();

      expect(prefs.getString('recording.follow'), isNull);
      expect(moves(h).last.arguments[2], 0);
      expect(chromeOf(tester).headingUp, isFalse);
      await unmountApp(tester);
    });

    testWidgets('the locate button only re-arms following', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot(headingDeg: 90));
      await settleCamera(tester, h);

      chromeOf(tester).onLocate!();
      await tester.pump();
      await settleAsync(tester);

      // The follow style is the compass button's business, not this one's.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recording.follow'), isNull);
      final chrome = chromeOf(tester);
      expect(chrome.headingUp, isFalse);
      expect(chrome.following, isTrue);
      await unmountApp(tester);
    });

    testWidgets('the needle follows the camera', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      expect(chromeOf(tester).bearingDeg, 0);

      h.map.bearing = 40;
      await settleCamera(tester, h);

      expect(chromeOf(tester).bearingDeg, 40);
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

      expect(chromeOf(tester).following, isFalse);
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
      expect(chromeOf(tester).following, isFalse);
      await unmountApp(tester);
    });

    testWidgets('an idle map never follows, and says so', (tester) async {
      await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();

      expect(chromeOf(tester).following, isFalse);
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

    testWidgets('a rider going against the route keeps their own course', (
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

      // Riding the route backwards: the road runs east, the rider goes west.
      // The cone must say west and the puck must be the fix, not the road.
      final snapshot = _snapshot(headingDeg: 260);
      await emitSnapshot(tester, h, snapshot);

      expect(pucks(h).last.arguments[0], snapshot.lastPosition);
      expect(pucks(h).last.arguments[1], 260);
      expect(moves(h).last.arguments[2], isNot(90));

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

  group('the compass at a standstill', () {
    /// Every camera move the screen asked for, in order.
    List<MapCall> moves(RecordingHarness h) =>
        h.map.calls.where((c) => c.method == 'moveTo').toList();

    /// Every puck the screen drew, in order.
    List<MapCall> pucks(RecordingHarness h) =>
        h.map.calls.where((c) => c.method == 'setPosition').toList();

    testWidgets('a rider who has stopped faces where the phone points', (
      tester,
    ) async {
      final h = RecordingHarness();
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      h.compass.point(90);
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(speedMps: 0));

      expect(pucks(h).last.arguments[1], 90);
      expect(
        pucks(h).last.arguments[3],
        isTrue,
        reason: 'the map may draw the cone however slow the rider is',
      );

      await unmountApp(tester);
    });

    testWidgets('heading-up turns the map to the phone at a standstill', (
      tester,
    ) async {
      final h = RecordingHarness();
      await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        harness: h,
        preferences: const {'recording.follow': 'headingUp'},
      );
      h.compass.point(90);
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(speedMps: 0));

      expect(moves(h).last.arguments[2], 90);

      await unmountApp(tester);
    });

    testWidgets('once the ride is moving the GPS course wins', (tester) async {
      final h = RecordingHarness();
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      h.compass.point(90);
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(speedMps: 0));
      await emitSnapshot(
        tester,
        h,
        _snapshot(
          speedMps: 5,
          headingDeg: 30,
          lastPosition: const LatLng(48.11, 11.21),
        ),
      );

      expect(pucks(h).last.arguments[1], 30);
      expect(pucks(h).last.arguments[3], isFalse);

      await unmountApp(tester);
    });

    testWidgets('turning the phone redraws the puck without a new fix', (
      tester,
    ) async {
      final h = RecordingHarness();
      await pumpRecordingScreen(tester, const RecordingScreen(), harness: h);
      h.compass.point(90);
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot(speedMps: 0));
      final drawn = pucks(h).length;

      h.compass.point(120);
      await tester.pump();
      await tester.pump();

      expect(pucks(h).length, greaterThan(drawn));
      expect(pucks(h).last.arguments[1], 120);
      expect(pucks(h).last.arguments[3], isTrue);

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
      expect(find.text(testHeight(200)), findsOneWidget);
      expect(find.text(l10n.navTurnLeft), findsOneWidget);
      // The column glides down under the banner.
      await tester.pump(const Duration(milliseconds: 300));
      expect(controlsTopOf(tester), turnBannerHeight + 24);

      await unmountApp(tester);
    });

    testWidgets('stays away when nothing is being guided', (tester) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot());

      expect(find.byType(TurnBanner), findsNothing);
      expect(controlsTopOf(tester), defaultMapControlsTop);

      await unmountApp(tester);
    });
  });

  group('the battery saver', () {
    /// Every puck push the screen made, in order.
    List<MapCall> pucks(RecordingHarness h) =>
        h.map.calls.where((c) => c.method == 'setPosition').toList();

    /// Every camera move, in order.
    List<MapCall> moves(RecordingHarness h) =>
        h.map.calls.where((c) => c.method == 'moveTo').toList();

    testWidgets('the idle sheet offers the switch and remembers it', (
      tester,
    ) async {
      await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();

      final tile = find.widgetWithText(SwitchListTile, l10n.gpsPrecisionSaver);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(RecordingScreen)),
      );
      expect(container.read(recordingSettingsProvider).saver, isTrue);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);

      await unmountApp(tester);
    });

    testWidgets('a ride started with it on records at the saver profile', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const <String, Object>{
          'recording.saver': true,
          'recording.precision': 'precise',
        },
      );
      await tester.pump();

      await tester.tap(find.text(l10n.recordingStart));
      await tester.pumpAndSettle();

      // The saver overrules the precision the rider picked.
      expect(h.service.precisions, [GpsPrecision.saver]);

      await unmountApp(tester);
    });

    testWidgets('the puck loses its ring and its cone, the camera its glide', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const <String, Object>{'recording.saver': true},
      );
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(headingDeg: 90));

      expect(pucks(h).last.arguments[4], isTrue, reason: 'the bare dot');
      expect(moves(h).last.arguments[4], isFalse, reason: 'no animation');
      expect(moves(h).last.arguments[3], isNull, reason: 'nothing to glide');

      await unmountApp(tester);
    });

    testWidgets('an ordinary ride keeps the ring and the glide', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();

      await emitSnapshot(tester, h, _snapshot(headingDeg: 90));

      expect(pucks(h).last.arguments[4], isFalse);
      expect(moves(h).last.arguments[4], isTrue);

      await unmountApp(tester);
    });

    testWidgets('the screen is dimmed while it is also held awake', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const <String, Object>{'recording.saver': true},
      );
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      expect(h.dimmer.brightness, isNull, reason: 'the screen may sleep');

      await tester.tap(
        find.widgetWithText(SwitchListTile, l10n.recordingKeepScreenOn),
      );
      await tester.pumpAndSettle();

      expect(h.dimmer.brightness, saverBrightness);

      // The ride ends: the rider's own brightness comes back.
      await emitSnapshot(tester, h, _snapshot(status: RecordingStatus.idle));

      expect(h.dimmer.brightness, isNull);
      expect(h.dimmer.calls, ['dim(0.4)', 'reset']);

      await unmountApp(tester);
    });

    testWidgets('after thirty seconds the figures are all that is left', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const <String, Object>{'recording.saver': true},
      );
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);

      await tester.pump(glanceAfter + const Duration(seconds: 1));

      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.text(l10n.statDistance.toUpperCase()), findsOneWidget);
      expect(find.text(testDistance(12345)), findsOneWidget);
      expect(find.text(l10n.statSpeed.toUpperCase()), findsOneWidget);
      // Nothing that could stop the ride by accident.
      expect(find.byTooltip(l10n.recordingFinish), findsNothing);
      // The shell's column is told to stay away; the map is the shell's and
      // stays under the black.
      expect(chromeOf(tester).visible, isFalse);

      await unmountApp(tester);
    });

    testWidgets('a tap brings the map back for another thirty seconds', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const <String, Object>{'recording.saver': true},
      );
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      await tester.pump(glanceAfter + const Duration(seconds: 1));
      expect(find.byType(DraggableScrollableSheet), findsNothing);

      await tester.tapAt(const Offset(500, 300));
      await tester.pump();

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);

      // And it goes again once the rider leaves it alone.
      await tester.pump(glanceAfter + const Duration(seconds: 1));
      expect(find.byType(DraggableScrollableSheet), findsNothing);

      await unmountApp(tester);
    });

    testWidgets('a ride without the saver keeps the map whatever happens', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(tester, const RecordingScreen());
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());

      await tester.pump(glanceAfter + const Duration(seconds: 1));

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(
        find.text(l10n.recordingStatusRecording.toUpperCase()),
        findsOneWidget,
      );

      await unmountApp(tester);
    });

    testWidgets('the ride ending puts the map and the sheet back', (
      tester,
    ) async {
      final h = await pumpRecordingScreen(
        tester,
        const RecordingScreen(),
        preferences: const <String, Object>{'recording.saver': true},
      );
      await tester.pump();
      await emitSnapshot(tester, h, _snapshot());
      await tester.pump(glanceAfter + const Duration(seconds: 1));
      expect(find.byType(DraggableScrollableSheet), findsNothing);

      await emitSnapshot(tester, h, _snapshot(status: RecordingStatus.idle));

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.text(l10n.recordingIdleTitle), findsOneWidget);

      await unmountApp(tester);
    });
  });

  testWidgets('a recorder that refuses to start shows why', (tester) async {
    final h = await pumpRecordingScreen(tester, const RecordingScreen());
    h.service.startError = const RecordingException('service timeout');
    await tester.pump();

    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();

    expect(find.text(l10n.recordingFailed('service timeout')), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the record sheet reads in miles, mph and feet under imperial', (
    tester,
  ) async {
    final h = await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      extraOverrides: [imperialUnits],
    );
    await tester.pump();

    await emitSnapshot(tester, h, _snapshot());

    // 12 345 m, 6 m/s, 5 m/s average, 210 m up and 190 m down.
    expect(
      find.text(testDistance(12345, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(
      find.text(testSpeed(6, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(
      find.text(testSpeed(5, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(
      find.text(testHeight(210, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(
      find.text(testHeight(190, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(find.textContaining('km'), findsNothing);

    await unmountApp(tester);
  });

  // Last on purpose: it swaps the test font for the real one, which every
  // test after it in this file would then lay out with.
  testWidgets('at rest on a 390 dp phone the idle sheet shows the chooser, '
      'the button and the switch without a scroll', (tester) async {
    // The stand-in font of a widget test gives every glyph a full em, so no
    // sentence would fit one line at 390 dp. Measure with the font the app
    // ships, at the weight of the small body text.
    final manrope = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-Medium.ttf'));
    await manrope.load();
    // The view agrees with the surface, so the sheet's fractions are real.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      surfaceSize: const Size(390, 844),
    );
    await tester.pumpAndSettle();
    expectNoClippedText(tester);

    // The line under the headline is one line, whichever hint is up.
    final shown = tester.widget<Text>(find.byKey(recordingIdleHintKey)).data;
    expect(idleHints(l10n), contains(shown));
    expect(idleHints(l10n), hasLength(idleHintCount));
    expect(
      tester.getSize(find.byKey(recordingIdleHintKey)).height,
      lessThan(20),
    );

    // And every hint in the rotation fits that line at this width.
    final style = tester.widget<Text>(find.byKey(recordingIdleHintKey)).style;
    for (final hint in idleHints(l10n)) {
      final painter = TextPainter(
        text: TextSpan(text: hint, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 390 - 40);
      expect(painter.computeLineMetrics(), hasLength(1), reason: hint);
    }

    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    final sheetTop = 844 * (1 - sheet.initialChildSize);
    final chooser = tester.getRect(find.byType(FollowRouteField));
    final start = tester.getRect(
      find.widgetWithText(FilledButton, l10n.recordingStart),
    );
    final keep = tester.getRect(
      find.widgetWithText(SwitchListTile, l10n.recordingKeepScreenOn),
    );
    // The chooser first, the button under it, the switch under that, all
    // inside the sheet at its resting height.
    expect(chooser.top, greaterThanOrEqualTo(sheetTop));
    expect(start.top, greaterThanOrEqualTo(chooser.bottom));
    expect(keep.top, greaterThanOrEqualTo(start.bottom));
    expect(keep.bottom, lessThanOrEqualTo(844));
    await unmountApp(tester);
  });
}
