// Guidance on the simulator's own GPS: a route planned on the device, the
// real geolocator riding along it with the map's stream open, the navigator,
// the banner and the spoken cues all on real fixes. The scripted twin of this
// (navigate_route_test.dart) drives the same chain from a fake position
// source and covers the detours; this one exists because the fake cannot see
// an iOS-only fault in the stream. Skipped off iOS.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/live_activity_state.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/live_activity.dart'
    show liveActivityAppGroupId;
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/sim_gps.dart';
import 'support/tiles.dart';

/// Long enough for a turn or two, short enough to ride at 6 m/s within the
/// file's budget.
const double _rideM = 900;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guides a ride on the simulator GPS along a planned route', (
    tester,
  ) async {
    if (!Platform.isIOS) {
      markTestSkipped('needs the iOS simulator and tool/sim_ride.py');
      return;
    }
    RecordingRecovery.overrideWith(
      Future<RecoveryResult>.value(const NoRecovery()),
    );
    addTearDown(RecordingRecovery.reset);
    final speaker = FakeTurnSpeaker();

    // Neither the position source nor the recorder is replaced.
    final container = await pumpApp(
      tester,
      overrides: [
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        notificationPermissionProvider.overrideWithValue(
          const GrantedNotificationPermission(),
        ),
        batteryOptimizationProvider.overrideWithValue(
          const ExemptBatteryOptimization(),
        ),
        screenWakeProvider.overrideWithValue(RecordingScreenWake()),
        turnSpeakerProvider.overrideWithValue(speaker),
        recordingRecoveryProvider.overrideWith(
          (ref) async => const NoRecovery(),
        ),
      ],
    );
    await ensureRegionTile(tester, container);
    final settings = container.read(navigationSettingsProvider.notifier);
    await settings.setTurns(true);
    await settings.setVoice(true);

    final planner = container.read(plannerControllerProvider.notifier);
    planner
      ..addWaypoint(region.start)
      ..addWaypoint(region.end);
    final far = await _routed(tester, container, describe: "the region's ends");
    planner.moveWaypoint(1, _pointAlong(far.positions, _rideM));
    final route = await _routed(
      tester,
      container,
      describe: 'the ride to $_rideM m',
    );
    final line = route.positions;
    debugPrint(
      'VELORKI_NAV route ${route.lengthM.round()}m ${line.length} points',
    );

    // Put the simulated rider on the route before the ride starts, so the
    // first fixes are already on it.
    await rideSimulatorAlong(tester, line);

    await tapAndPump(tester, find.text('Record'));
    final sheet = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.dragUntilVisible(
      find.widgetWithText(FilledButton, 'Start ride'),
      sheet,
      const Offset(0, 220),
    );
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Start ride'));
    await waitForWidget(tester, find.text('RECORDING'));

    // The banner comes up on the route and is not off it.
    await waitUntil(
      tester,
      () => _progress(tester) != null,
      describe: 'the turn banner to appear',
      timeout: const Duration(seconds: 60),
      onTimeout: () => '${container.read(navigationControllerProvider)}',
    );
    await waitUntil(
      tester,
      () => _progress(tester)?.offRoute == false,
      describe: 'the rider to be on the route',
      timeout: const Duration(seconds: 60),
      onTimeout: () => '${_progress(tester)}',
    );

    // Something gets said, and the ride covers ground meanwhile.
    final recording = container.listen(recordingControllerProvider, (_, _) {});
    addTearDown(recording.close);
    await waitUntil(
      tester,
      () => speaker.spoken.isNotEmpty,
      describe: 'a cue to be spoken from the real GPS',
      timeout: const Duration(seconds: 120),
      onTimeout: () => '${_progress(tester)} / ${recording.read().snapshot}',
    );
    expect(recording.read().snapshot?.distanceM ?? 0, greaterThan(30));
    debugPrint('VELORKI_NAV spoken: ${speaker.spoken}');

    // The card is up, with the ride.
    final activities = LiveActivities();
    await activities.init(appGroupId: liveActivityAppGroupId);
    final ids = await activities.getAllActivitiesIds();
    expect(ids, hasLength(1));
    expect(
      await activities.getActivityState(ids.single),
      LiveActivityState.active,
    );

    await tapAndPump(
      tester,
      find.byTooltip('Finish'),
      settle: const Duration(seconds: 2),
    );
    await waitForWidget(tester, find.byType(SaveRideSheet));
    await tapAndPump(
      tester,
      find.widgetWithText(FilledButton, 'Save'),
      settle: const Duration(seconds: 2),
    );
    await waitUntil(
      tester,
      () => !recording.read().isRecording,
      describe: 'the ride to finish',
    );
    await unmountApp(tester);
  });
}

NavigationProgress? _progress(WidgetTester tester) {
  final banner = find.byType(TurnBanner).evaluate();
  if (banner.isEmpty) return null;
  return (banner.first.widget as TurnBanner).progress;
}

Future<RouteResult> _routed(
  WidgetTester tester,
  ProviderContainer container, {
  required String describe,
}) async {
  await pumpFor(tester, const Duration(milliseconds: 400));
  await waitUntil(
    tester,
    () {
      final state = container.read(plannerControllerProvider);
      if (state.route.hasError) fail('routing failed: ${state.route.error}');
      return state.result != null && !state.isRouting;
    },
    describe: 'the on-device router to answer for $describe',
    timeout: const Duration(seconds: 90),
    onTimeout: () => '${container.read(plannerControllerProvider).route}',
  );
  return container.read(plannerControllerProvider).result!;
}

LatLng _pointAlong(List<LatLng> line, double metres) {
  var covered = 0.0;
  for (var i = 1; i < line.length; i++) {
    covered += haversineMeters(line[i - 1], line[i]);
    if (covered >= metres) return line[i];
  }
  return line.last;
}
