// A ride on the simulator's own GPS with the phone's health store connected:
// the real geolocator, the real recorder, the real SensorHub and the real
// HealthSensorSource poll, all the way to the heart rate on the record sheet,
// in the saved ride's statistics, on the ride page's chart, and back out as a
// cycling workout.
//
// Only the plugin behind the health store is replaced: HealthKit cannot be
// written from a test runner, and its permission sheet is system UI nothing
// can tap. `healthGatewayProvider` therefore hands out a FakeHealthGateway
// that reports authorization granted and answers every poll with a fresh
// 140 bpm sample — which is exactly what a paired watch looks like to this
// app. Health is switched on through the stored preferences rather than by
// tapping the switch, for the same reason: turning it on is what raises the
// OS prompt.
//
// tool/sim_ride.py walks the simulated location along the region's route and
// grants the location permission the moment the app is installed. On any
// other device the test is skipped.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki/features/sensors/application/sensor_sources_controller.dart';
import 'package:velorki/features/sensors/data/health_gateway.dart';
import 'package:velorki/features/sensors/testing/fake_health_gateway.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

const Set<geo.LocationPermission> _granted = <geo.LocationPermission>{
  geo.LocationPermission.whileInUse,
  geo.LocationPermission.always,
};

/// What the scripted store reports, and what every assertion looks for.
const int _bpm = 140;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a ride with Health on takes the heart rate from the store and '
      'writes the ride back as a workout', (tester) async {
    if (!Platform.isIOS) {
      markTestSkipped('needs the iOS simulator and tool/sim_ride.py');
      return;
    }
    RecordingRecovery.overrideWith(
      Future<RecoveryResult>.value(const NoRecovery()),
    );
    addTearDown(RecordingRecovery.reset);

    // Health on, rides written back. Seeded rather than tapped: the switch is
    // the one thing in the app that raises the OS permission sheet, and the
    // device keeps its preferences between runs, so both keys are set here
    // rather than trusted.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sensors.health', true);
    await prefs.remove('sensors.health.write');

    // A store that keeps being written to, the way a watch writes to it: every
    // poll finds one sample it has not seen, a second old.
    final gateway = FakeHealthGateway(granted: true);
    gateway.onQuery = (from, to) => gateway.samples.add(
      HeartRateSample(
        bpm: _bpm,
        at: to.subtract(const Duration(seconds: 1)),
        sourceName: 'Itest watch',
      ),
    );

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
        healthGatewayProvider.overrideWithValue(gateway),
      ],
    );
    // `bootstrap()` does this in the app; `pumpApp` builds its own container
    // and never runs it. Without the read nothing observes the switch, and the
    // health source would never be registered with the hub.
    container.read(sensorSourcesProvider);

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

    // The finished ride is the one that was not in the database before.
    final rides = container.listen(ridesProvider, (_, _) {});
    addTearDown(rides.close);
    await waitUntil(
      tester,
      () => rides.read().hasValue,
      describe: 'the rides already in the database',
      onTimeout: () => '${rides.read()}',
    );
    final before = {for (final ride in rides.read().requireValue) ride.id};

    // ---------------------------------------------------------------- start
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

    // --------------------------------------------------- the heart rate tile
    // The third stat row only exists once a sensor has reported, so finding
    // the tile at all is half the assertion.
    await waitUntil(
      tester,
      () => find.text('$_bpm bpm').evaluate().isNotEmpty,
      describe: 'the record sheet to show $_bpm bpm',
      timeout: const Duration(seconds: 90),
      onTimeout: () =>
          'polls=${gateway.queries.length} '
          'snapshot=${recording.read().snapshot}',
    );
    final tile = tester.widget<StatTile>(
      find.ancestor(
        of: find.text('HEART RATE'),
        matching: find.byType(StatTile),
      ),
    );
    expect(tile.label, 'Heart rate');
    expect(tile.value, '$_bpm bpm');
    debugPrint(
      'VELORKI_HEALTH ${gateway.queries.length} poll(s) for ${tile.value}',
    );
    await screenshot(tester, 'recording-heart-rate');

    // --------------------------------------------------------------- finish
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
    await waitUntil(
      tester,
      () => (rides.read().value ?? const <Ride>[]).any(
        (ride) => !before.contains(ride.id),
      ),
      describe: 'the finished ride in the database',
      onTimeout: () => '${rides.read()}',
    );
    final ride = rides.read().value!.firstWhere(
      (ride) => !before.contains(ride.id),
    );
    debugPrint(
      'VELORKI_HEALTH saved ${ride.name}: '
      '${ride.stats.distanceM.round()}m, hr=${ride.stats.avgHeartRateBpm}',
    );

    // The fixes were stamped live from the hub, and whatever the post-ride
    // sync filled came out of the same store, so either way it is one number.
    await waitUntil(
      tester,
      () =>
          (rides.read().value ?? const <Ride>[])
              .firstWhere((r) => r.id == ride.id)
              .stats
              .avgHeartRateBpm ==
          _bpm,
      describe: 'the saved ride to average $_bpm bpm',
      onTimeout: () => '${ride.stats}',
    );

    // ------------------------------------------------- the ride in the library
    await tapAndPump(tester, find.text('Library'));
    // The Library remembers its last segment across launches; this one wants
    // the rides.
    await tapAndPump(tester, find.text('Rides'));
    final row = find.byKey(ValueKey('ride-${ride.id}'));
    await waitForWidget(tester, row);
    await tapAndPump(tester, row);

    // The chart draws nothing without at least two fixes carrying a reading,
    // so its presence is the proof the whole track was stamped.
    await waitForWidget(
      tester,
      find.byType(RideHeartRateChart),
      timeout: const Duration(seconds: 30),
    );
    await screenshot(tester, 'ride-heart-rate-chart');

    // ------------------------------------------------------------ the workout
    await waitUntil(
      tester,
      () => gateway.workouts.isNotEmpty,
      describe: 'the ride to be written back as a workout',
      onTimeout: () => 'nothing written; queries=${gateway.queries.length}',
    );
    expect(
      gateway.workouts,
      hasLength(1),
      reason: 'once per ride, never twice',
    );
    final workout = gateway.workouts.single;
    expect(workout.start, ride.startedAt);
    expect(workout.end, ride.endedAt);
    expect(workout.distanceM, closeTo(ride.stats.distanceM, 1));
    expect(workout.avgHeartRateBpm, _bpm.toDouble());
    // Nothing tapped the switch, so nothing asked the OS for anything.
    expect(gateway.authorizations, isEmpty);

    await unmountApp(tester);
  });
}
