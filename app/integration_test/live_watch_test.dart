// A ride steered from the wrist: the real geolocator, the real recorder, the
// real SensorHub and the real WatchRideBridge, from a tap on the watch through
// the heart rate on the record sheet to the saved ride's statistics.
//
// Only the link to the watch is replaced. There is no watch on a CI machine
// and a paired watch simulator cannot be driven from a test runner, so
// `watchGatewayProvider` hands out a FakeWatchGateway that reports a paired,
// reachable watch, writes down everything the phone sends it and plays the
// watch's own messages back — which is exactly what the watch app does over
// WatchConnectivity. The switch is set through the stored preferences rather
// than tapped, the way the Health test does it, because the device keeps its
// preferences between runs.
//
// tool/sim_ride.py walks the simulated location along the region's route and
// grants the location permission the moment the app is installed. On any
// other device the test is skipped.
import 'dart:async';
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
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki/features/sensors/application/watch_ride_bridge.dart';
import 'package:velorki/features/sensors/data/watch_gateway.dart';
import 'package:velorki/features/sensors/data/watch_protocol.dart';
import 'package:velorki/features/sensors/testing/fake_watch_gateway.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

const Set<geo.LocationPermission> _granted = <geo.LocationPermission>{
  geo.LocationPermission.whileInUse,
  geo.LocationPermission.always,
};

/// What the watch reports, and what every assertion looks for.
const int _bpm = 150;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a ride started, paused and measured from the watch', (
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

    // The watch is on; nothing else about sensors is.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sensors.watch', true);
    await prefs.remove('sensors.health');

    final watch = FakeWatchGateway();
    addTearDown(watch.dispose);

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
        watchGatewayProvider.overrideWithValue(watch),
      ],
    );
    // `bootstrap()` does this in the app; `pumpApp` builds its own container
    // and never runs it. Without the read nothing listens to the watch.
    container.read(watchRideBridgeProvider);

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

    // The record tab is where the ride shows up; nothing is tapped on it.
    await tapAndPump(tester, find.text('Record'));
    await waitForWidget(
      tester,
      find.widgetWithText(FilledButton, 'Start ride'),
    );

    // --------------------------------------------------- start from the wrist
    watch.receive(<String, Object?>{
      watchTypeKey: watchCommandType,
      watchCommandKey: watchCommandStart,
    });
    await waitForWidget(tester, find.text('RECORDING'));

    // The watch is asked to measure as soon as the ride runs.
    await waitUntil(
      tester,
      () => watch.sent.any(
        (m) =>
            m[watchTypeKey] == watchWorkoutType &&
            m[watchWorkoutActionKey] == watchWorkoutStart,
      ),
      describe: 'the phone to ask the watch for a workout',
      onTimeout: () => '${watch.sent}',
    );

    // A watch that measures every second, which is what the real one does.
    final beats = Timer.periodic(const Duration(seconds: 1), (_) {
      watch.receive(<String, Object?>{
        watchTypeKey: watchHeartRateType,
        watchBpmKey: _bpm,
        watchAtKey: DateTime.now().toUtc().millisecondsSinceEpoch,
      });
    });
    addTearDown(beats.cancel);

    // ---------------------------------------------------- the heart rate tile
    // The third stat row only exists once a sensor has reported, so finding
    // the tile at all is half the assertion.
    await waitUntil(
      tester,
      () => find.text('$_bpm bpm').evaluate().isNotEmpty,
      describe: 'the record sheet to show $_bpm bpm',
      timeout: const Duration(seconds: 60),
      onTimeout: () =>
          '${container.read(recordingControllerProvider).snapshot}',
    );
    final tile = tester.widget<StatTile>(
      find.ancestor(
        of: find.text('HEART RATE'),
        matching: find.byType(StatTile),
      ),
    );
    expect(tile.value, '$_bpm bpm');
    await screenshot(tester, 'watch-heart-rate');

    // ------------------------------------------------- what the watch is told
    final recording = container.listen(recordingControllerProvider, (_, _) {});
    addTearDown(recording.close);
    await waitUntil(
      tester,
      () => watch.contexts.any(
        (context) =>
            context[watchStatusKey] == watchStatusActive &&
            (context[watchDistanceKey] as String? ?? '').isNotEmpty,
      ),
      describe: 'the watch to be given the running ride',
      onTimeout: () => '${watch.contexts}',
    );
    final live = watch.contexts.lastWhere(
      (context) => context[watchStatusKey] == watchStatusActive,
    );
    // Formatted by the phone, in the phone's units: the watch does no
    // arithmetic of its own.
    expect(live[watchDistanceKey], matches(r'^[\d.,]+ (m|km)$'));
    expect(live[watchElapsedKey], matches(r'^\d+:\d\d$'));

    // ----------------------------------------------- pause and resume from it
    watch.receive(<String, Object?>{
      watchTypeKey: watchCommandType,
      watchCommandKey: watchCommandPause,
    });
    await waitForWidget(tester, find.text('PAUSED'));
    expect(
      watch.contexts.last[watchStatusKey],
      watchStatusPaused,
      reason: 'the wrist shows what the phone is doing',
    );

    watch.receive(<String, Object?>{
      watchTypeKey: watchCommandType,
      watchCommandKey: watchCommandResume,
    });
    await waitForWidget(tester, find.text('RECORDING'));

    // The simulated rider does 6 m/s; 50 m is well clear of any GPS noise
    // and arrives within the minute even with a slow first fix.
    await waitUntil(
      tester,
      () => (recording.read().snapshot?.distanceM ?? 0) > 50,
      describe: 'the ride to cover 50 m from the simulator GPS',
      timeout: const Duration(seconds: 90),
      onTimeout: () => '${recording.read().snapshot}',
    );

    // --------------------------------------------------------------- finish
    // On the phone, because the ride is named here and the sheet is what
    // names it; the watch's own Finish only gets the rider this far.
    beats.cancel();
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

    // The ride is over, so the watch is told to stop measuring.
    await waitUntil(
      tester,
      () => watch.sent.any(
        (m) =>
            m[watchTypeKey] == watchWorkoutType &&
            m[watchWorkoutActionKey] == watchWorkoutStop,
      ),
      describe: 'the phone to end the watch workout',
      onTimeout: () => '${watch.sent}',
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
      'VELORKI_WATCH saved ${ride.name}: '
      '${ride.stats.distanceM.round()}m, hr=${ride.stats.avgHeartRateBpm}',
    );
    // Every fix was stamped from the hub, and only the watch was reporting.
    expect(ride.stats.avgHeartRateBpm, _bpm);

    await unmountApp(tester);
  });
}
