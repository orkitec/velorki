import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/sensors/data/ble_gateway.dart';
import 'package:velorki/features/sensors/data/paired_sensors.dart';
import 'package:velorki/features/sensors/data/sensor_settings.dart';
import 'package:velorki/features/sensors/domain/ble_profiles.dart';
import 'package:velorki/features/sensors/domain/sensor_reading.dart';
import 'package:velorki/features/sensors/presentation/ble_sensors_screen.dart';
import 'package:velorki/features/sensors/testing/fake_ble_gateway.dart';

import '../../support/app.dart';
import '../recording/support/fakes.dart';

const String _strapId = 'aa:bb';
const String _wheelId = 'ee:ff';

String _stored(List<Map<String, Object>> devices) => jsonEncode(devices);

Map<String, Object> _strap() => <String, Object>{
  'id': _strapId,
  'name': 'Chest Strap',
  'kinds': <String>['heartRate'],
};

Map<String, Object> _wheel() => <String, Object>{
  'id': _wheelId,
  'name': 'Wheel',
  'kinds': <String>['speed', 'cadence'],
};

void main() {
  late FakeBleGateway gateway;
  late FakeRecordingService service;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<Map<String, Object>> paired = const <Map<String, Object>>[],
    List<FakeBleDevice> devices = const <FakeBleDevice>[],
    bool permitted = true,
    bool on = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (paired.isNotEmpty) prefsPairedSensors: _stored(paired),
    });
    final prefs = await SharedPreferences.getInstance();
    gateway = FakeBleGateway(devices: devices, permitted: permitted, on: on);
    addTearDown(gateway.dispose);
    service = FakeRecordingService();
    addTearDown(service.dispose);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        recordingServiceProvider.overrideWithValue(service),
        bleGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(home: const BleSensorsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expectNoClippedText(tester);
    return container;
  }

  /// Taps Scan and lets the search run its course.
  Future<void> scan(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, l10n.bleScan));
    await tester.pumpAndSettle();
  }

  Future<void> finishScan(WidgetTester tester) async {
    await tester.pump(bleScanDuration);
    await tester.pumpAndSettle();
  }

  testWidgets('starts with nothing paired and nothing found', (tester) async {
    await pump(tester);

    expect(find.text(l10n.bleNothingPaired), findsOneWidget);
    expect(find.text(l10n.blePaired.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.bleFound.toUpperCase()), findsNothing);
    expect(gateway.permissionRequests, 0, reason: 'nothing was asked for');
    expect(gateway.scans, isEmpty);
  });

  testWidgets('scanning asks for permission once and lists what it hears', (
    tester,
  ) async {
    await pump(
      tester,
      devices: <FakeBleDevice>[
        FakeBleDevice.strap(id: _strapId, name: 'Chest Strap', rssi: -50),
        FakeBleDevice.power(id: 'cc:dd', name: 'Power Meter', rssi: -80),
      ],
    );

    await scan(tester);

    expect(gateway.permissionRequests, 1);
    expect(gateway.scans.single, bleSensorServiceUuids);
    expect(find.text('Chest Strap'), findsOneWidget);
    expect(find.text('Power Meter'), findsOneWidget);
    expect(find.text(l10n.bleSignal(-50)), findsOneWidget);
    // The nearer device is offered first.
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(names.first, 'Chest Strap');

    await finishScan(tester);
    expect(find.text(l10n.bleScan), findsOneWidget, reason: 'the scan ended');
  });

  testWidgets('a refused permission scans nothing and says so', (tester) async {
    await pump(
      tester,
      permitted: false,
      devices: <FakeBleDevice>[FakeBleDevice.strap(id: _strapId)],
    );

    await scan(tester);

    expect(gateway.scans, isEmpty);
    expect(find.text(l10n.blePermissionDenied), findsOneWidget);
  });

  testWidgets('a radio that is switched off scans nothing and says so', (
    tester,
  ) async {
    await pump(
      tester,
      on: false,
      devices: <FakeBleDevice>[FakeBleDevice.strap(id: _strapId)],
    );

    await scan(tester);

    expect(gateway.scans, isEmpty);
    expect(find.text(l10n.bleAdapterOff), findsOneWidget);
  });

  testWidgets('pairing stores what the device actually has', (tester) async {
    final container = await pump(
      tester,
      devices: <FakeBleDevice>[
        FakeBleDevice.power(id: 'cc:dd', name: 'Power Meter'),
      ],
    );

    await scan(tester);
    await tester.tap(find.text('Power Meter'));
    await tester.pumpAndSettle();

    final paired = container.read(pairedSensorsProvider).single;
    expect(paired.id, 'cc:dd');
    expect(paired.name, 'Power Meter');
    expect(paired.kinds, <SensorKind>{SensorKind.power, SensorKind.cadence});
    // It moves out of the found list and into the paired one.
    expect(find.text(l10n.bleNothingPaired), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(prefsPairedSensors),
      contains('cc:dd'),
    );

    await finishScan(tester);
  });

  testWidgets('a paired sensor shows where its link stands', (tester) async {
    await pump(
      tester,
      paired: <Map<String, Object>>[_strap()],
      devices: <FakeBleDevice>[FakeBleDevice.strap(id: _strapId)],
    );
    await tester.pumpAndSettle();

    expect(find.text('Chest Strap'), findsOneWidget);
    // The screen holds the link open while it is on screen.
    expect(find.text(l10n.bleConnected), findsOneWidget);
  });

  testWidgets('forgetting removes it from the list and the preferences', (
    tester,
  ) async {
    final container = await pump(
      tester,
      paired: <Map<String, Object>>[_strap()],
      devices: <FakeBleDevice>[FakeBleDevice.strap(id: _strapId)],
    );

    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.bleForget));
    await tester.pumpAndSettle();

    expect(container.read(pairedSensorsProvider), isEmpty);
    expect(find.text('Chest Strap'), findsNothing);
    expect(find.text(l10n.bleNothingPaired), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString(prefsPairedSensors),
      isNull,
    );
  });

  testWidgets('the wheel is only asked about once a speed sensor is paired', (
    tester,
  ) async {
    await pump(tester, paired: <Map<String, Object>>[_strap()]);
    expect(find.text(l10n.bleWheelCircumference), findsNothing);
  });

  testWidgets('editing the wheel circumference stores it', (tester) async {
    final container = await pump(
      tester,
      paired: <Map<String, Object>>[_wheel()],
      devices: <FakeBleDevice>[FakeBleDevice.cadence(id: _wheelId)],
    );

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      '$defaultWheelCircumferenceMm',
    );

    await tester.enterText(field, '2326');
    await tester.pumpAndSettle();

    expect(container.read(sensorSettingsProvider).wheelCircumferenceMm, 2326);
    expect(
      (await SharedPreferences.getInstance()).getInt(prefsWheelCircumferenceMm),
      2326,
    );

    // Half a number is not a correction.
    await tester.enterText(field, '23');
    await tester.pumpAndSettle();
    expect(container.read(sensorSettingsProvider).wheelCircumferenceMm, 2326);
  });
}
