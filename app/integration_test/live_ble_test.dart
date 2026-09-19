// A ride with a Bluetooth sensor on it: the real geolocator, the real
// recorder, the real SensorHub and the real BleSensorSource, from the GATT
// packets on the air to the three tiles on the record sheet and the averages
// of the saved ride.
//
// Only the radio is replaced. A CI machine has no heart-rate strap and the
// simulator has no Bluetooth at all, so `bleGatewayProvider` hands out a
// FakeBleGateway holding one device that offers the Heart Rate and Cycling
// Power services — a strap and a power meter in one, which is what a rider
// with both looks like to the hub. Its notifications are the real byte
// layouts with the real cumulative counters, so the cadence on the tile has
// been through the same parser a real meter's packets would be.
//
// The device is paired through the stored preferences rather than by tapping
// Scan, the way the Health test switches Health on: the Scan button is the one
// thing in this feature that raises the OS permission sheet, and that sheet is
// system UI nothing can tap.
//
// tool/sim_ride.py walks the simulated location along the region's route and
// grants the location permission the moment the app is installed. On any
// other device the test is skipped.
import 'dart:async';
import 'dart:convert';
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
import 'package:velorki/features/sensors/application/ble_sources_controller.dart';
import 'package:velorki/features/sensors/application/sensor_hub.dart';
import 'package:velorki/features/sensors/data/ble_gateway.dart';
import 'package:velorki/features/sensors/data/paired_sensors.dart';
import 'package:velorki/features/sensors/domain/ble_profiles.dart';
import 'package:velorki/features/sensors/testing/fake_ble_gateway.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

const Set<geo.LocationPermission> _granted = <geo.LocationPermission>{
  geo.LocationPermission.whileInUse,
  geo.LocationPermission.always,
};

/// The device the preferences say is paired, and the fake says is in the room.
const String _deviceId = 'itest-ble-sensor';

/// What the scripted sensor reports, and what every assertion looks for.
const int _bpm = 155;
const double _rpm = 85;
const int _watts = 210;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a ride measured by a Bluetooth strap and power meter', (
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

    // One paired sensor; nothing else about sensors is on, so every figure on
    // the sheet can only have come over Bluetooth.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsPairedSensors,
      jsonEncode(<Object>[
        <String, Object>{
          'id': _deviceId,
          'name': 'Itest Sensor',
          'kinds': <String>['heartRate', 'power', 'cadence'],
        },
      ]),
    );
    await prefs.remove('sensors.health');
    await prefs.remove('sensors.watch');

    final ble = FakeBleGateway(
      devices: <FakeBleDevice>[
        FakeBleDevice(
          id: _deviceId,
          name: 'Itest Sensor',
          serviceUuids: <String>{heartRateServiceUuid, cyclingPowerServiceUuid},
        ),
      ],
    );
    addTearDown(ble.dispose);

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
        bleGatewayProvider.overrideWithValue(ble),
      ],
    );
    // `bootstrap()` does this in the app; `pumpApp` builds its own container
    // and never runs it. Without the read nothing connects the paired device.
    container.read(bleSourcesProvider);

    // A sensor that reports once a second, which is what a real one does. The
    // counters are the sensor's own, so the cadence is derived rather than
    // handed over.
    final packets = Timer.periodic(const Duration(seconds: 1), (_) {
      ble
        ..beat(_deviceId, _bpm)
        ..watts(_deviceId, _watts, cadenceRpm: _rpm);
    });
    addTearDown(packets.cancel);

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
    // Nothing was connected to until now: no ride, and the sensors screen was
    // never opened.
    expect(ble.connects, isEmpty);

    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Start ride'));
    await waitForWidget(tester, find.text('RECORDING'));

    // -------------------------------------------------------------- the tiles
    // The sensor row only exists once something has reported, so finding the
    // tiles at all is half the assertion.
    await waitUntil(
      tester,
      () =>
          find.text('$_bpm bpm').evaluate().isNotEmpty &&
          find.text('${_rpm.round()} rpm').evaluate().isNotEmpty &&
          find.text('$_watts W').evaluate().isNotEmpty,
      describe: 'the record sheet to show what the sensor is reporting',
      timeout: const Duration(seconds: 60),
      onTimeout: () => '${container.read(sensorHubProvider)}',
    );
    StatTile tileOf(String label) => tester.widget<StatTile>(
      find.ancestor(of: find.text(label), matching: find.byType(StatTile)),
    );
    expect(tileOf('HEART RATE').value, '$_bpm bpm');
    expect(tileOf('CADENCE').value, '${_rpm.round()} rpm');
    expect(tileOf('POWER').value, '$_watts W');
    await screenshot(tester, 'ble-sensors');

    // ------------------------------------------------------------ a drop out
    // A strap carried out of range mid-ride, and come back for on the backoff.
    final droppedAt = container.read(sensorHubProvider).heartRateAt;
    expect(droppedAt, isNotNull);
    ble.drop(_deviceId);
    await waitUntil(
      tester,
      () => ble.connects.length > 1,
      describe: 'the source to reconnect',
      timeout: const Duration(seconds: 15),
      onTimeout: () => '${ble.connects}',
    );
    await waitUntil(
      tester,
      () => (container.read(sensorHubProvider).heartRateAt ?? droppedAt!)
          .isAfter(droppedAt!),
      describe: 'the readings to come back',
      timeout: const Duration(seconds: 15),
      onTimeout: () => '${container.read(sensorHubProvider)}',
    );

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
    packets.cancel();

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
      'VELORKI_BLE saved ${ride.name}: ${ride.stats.distanceM.round()}m, '
      'hr=${ride.stats.avgHeartRateBpm} cad=${ride.stats.avgCadenceRpm} '
      'pwr=${ride.stats.avgPowerW}',
    );
    // Every fix was stamped from the hub, and only the one sensor reported.
    expect(ride.stats.avgHeartRateBpm, _bpm);
    expect(ride.stats.avgCadenceRpm, _rpm.round());
    expect(ride.stats.avgPowerW, _watts);

    // The ride is over and the screen is not the sensors screen, so nothing is
    // connected any more.
    await waitUntil(
      tester,
      () => !ble.isConnected(_deviceId),
      describe: 'the sensor to be let go of',
    );

    await unmountApp(tester);
  });
}
