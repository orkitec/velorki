// A ride on the simulator's own GPS: the real geolocator, the real recorder,
// the map's own position stream open on the Record tab. Nothing about
// positions is faked, which is the point: geolocator on iOS allows one
// position stream, and a recorder that opens a second one records nothing
// (see SharedPositionSource). The fake-position tests cannot see that.
//
// tool/sim_ride.py walks the simulated location along the region's route and
// grants the location permission the moment the app is installed; the app's
// own permission prompt is faked away, since an alert is nothing a test can
// tap. On any other device the test is skipped.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:integration_test/integration_test.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/live_activity_state.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/heading_smoother.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/live_activity.dart'
    show liveActivityAppGroupId;
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

const Set<geo.LocationPermission> _granted = <geo.LocationPermission>{
  geo.LocationPermission.whileInUse,
  geo.LocationPermission.always,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a ride on the simulator GPS records distance and puts up a Live '
      'Activity', (tester) async {
    if (!Platform.isIOS) {
      markTestSkipped('needs the iOS simulator and tool/sim_ride.py');
      return;
    }
    RecordingRecovery.overrideWith(
      Future<RecoveryResult>.value(const NoRecovery()),
    );
    addTearDown(RecordingRecovery.reset);

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
        recordingRecoveryProvider.overrideWith(
          (ref) async => const NoRecovery(),
        ),
      ],
    );

    // Wait for the runner's grant to land rather than assume it.
    final clock = Stopwatch()..start();
    var permission = await geo.Geolocator.checkPermission();
    while (!_granted.contains(permission) &&
        clock.elapsed < const Duration(seconds: 120)) {
      await pumpFor(tester, const Duration(seconds: 2));
      permission = await geo.Geolocator.checkPermission();
    }
    expect(
      _granted,
      contains(permission),
      reason:
          'tool/sim_ride.py grants the location permission after the '
          'install; is it running?',
    );

    await tapAndPump(tester, find.text('Record'));
    await waitForWidget(
      tester,
      find.widgetWithText(FilledButton, 'Start ride'),
    );
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Start ride'));
    await waitForWidget(tester, find.text('RECORDING'));

    // The simulated rider does 6 m/s; 50 m is well clear of any GPS noise
    // and arrives within the minute even with a slow first fix.
    final recording = container.listen(recordingControllerProvider, (_, _) {});
    addTearDown(recording.close);
    await waitUntil(
      tester,
      () => (recording.read().snapshot?.distanceM ?? 0) > 50,
      describe: 'the ride to cover 50 m from the simulator GPS',
      timeout: const Duration(seconds: 90),
      onTimeout: () => '${recording.read().snapshot}',
    );

    // The recorder owns the puck while the ride runs, and the puck carries
    // its heading: the cone is read back from the map's renderer, which
    // draws nothing for a cone layer whose bitmap the style never got —
    // every write to it looks right then, and a ride once went without one.
    double? cone;
    final coneClock = Stopwatch()..start();
    while (cone == null && coneClock.elapsed < const Duration(seconds: 20)) {
      final map = container.read(sharedMapControllerProvider);
      if (map is MaplibreMapControllerAdapter) {
        cone = await map.renderedConeHeading();
      }
      if (cone == null) await pumpFor(tester, const Duration(seconds: 1));
    }
    expect(
      cone,
      isNotNull,
      reason: 'the map drew no heading cone at the puck while recording',
    );
    final course = recording.read().snapshot?.headingDeg;
    if (course != null) {
      expect(headingDifference(cone!, course), lessThan(45));
    }

    // The lock-screen card exists and is live while the ride runs. The
    // plugin lists activities by ActivityKit's own id, so there is exactly
    // one and it is active; the name the app requested it under is not it.
    final activities = LiveActivities();
    await activities.init(appGroupId: liveActivityAppGroupId);
    expect(await activities.areActivitiesSupported(), isTrue);
    final ids = await activities.getAllActivitiesIds();
    expect(ids, hasLength(1), reason: 'one ride, one card');
    expect(
      await activities.getActivityState(ids.single),
      LiveActivityState.active,
    );

    await tapAndPump(tester, find.byTooltip('Finish'));
    await waitForWidget(tester, find.byType(SaveRideSheet));
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Save'));
    await waitUntil(
      tester,
      () => !recording.read().isRecording,
      describe: 'the ride to finish',
    );

    // ...and goes with the ride, once ActivityKit has caught up.
    await pumpFor(tester, const Duration(seconds: 2));
    expect(await activities.getAllActivitiesIds(), isEmpty);
    await unmountApp(tester);
  });
}
