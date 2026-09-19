import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/sensors/data/ble_sensor_source.dart';
import 'package:velorki/features/sensors/data/paired_sensors.dart';
import 'package:velorki/features/sensors/domain/sensor_reading.dart';
import 'package:velorki/features/sensors/domain/sensor_source.dart';
import 'package:velorki/features/sensors/testing/fake_ble_gateway.dart';

const String _deviceId = 'aa:bb:cc';

PairedSensor _paired(Set<SensorKind> kinds) =>
    PairedSensor(id: _deviceId, name: 'Strap', kinds: kinds);

void main() {
  late FakeBleGateway gateway;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 9, 18, 9);
    gateway = FakeBleGateway();
  });

  tearDown(() => gateway.dispose());

  /// A source over the fake. Not torn down here: the tests that drive it
  /// through `fakeAsync` have to dispose of it inside that zone, because a
  /// future made there is only ever completed there.
  BleSensorSource source(PairedSensor device, {double wheelM = 2.105}) =>
      BleSensorSource(
        gateway: gateway,
        device: device,
        wheelCircumferenceM: () => wheelM,
        clock: () => now,
      );

  test('registers itself under its device id, at the Bluetooth rank', () {
    final ble = source(_paired(<SensorKind>{SensorKind.heartRate}));
    expect(ble.id, 'ble:$_deviceId');
    expect(ble.id, bleSensorSourceId(_deviceId));
    expect(ble.priority, bluetoothSensorPriority);
    expect(ble.name, 'Strap');
  });

  test('turns heart rate notifications into readings', () async {
    gateway.devices.add(FakeBleDevice.strap(id: _deviceId, name: 'Strap'));
    final ble = source(_paired(<SensorKind>{SensorKind.heartRate}));
    final readings = <SensorReading>[];
    ble.readings.listen(readings.add);
    await ble.start();
    expect(ble.isConnected, isTrue);

    gateway.beat(_deviceId, 152);
    await pumpEventQueue();

    expect(readings, hasLength(1));
    expect(readings.single.kind, SensorKind.heartRate);
    expect(readings.single.value, 152);
    expect(readings.single.sourceId, 'ble:$_deviceId');
    expect(readings.single.at, now);
    await ble.dispose();
  });

  test(
    'a strap that has lost contact reports nothing rather than zero',
    () async {
      gateway.devices.add(FakeBleDevice.strap(id: _deviceId));
      final ble = source(_paired(<SensorKind>{SensorKind.heartRate}));
      final readings = <SensorReading>[];
      ble.readings.listen(readings.add);
      await ble.start();

      gateway.beat(_deviceId, 0);
      await pumpEventQueue();

      expect(readings, isEmpty);
      await ble.dispose();
    },
  );

  test('derives speed and cadence from a speed and cadence sensor', () async {
    gateway.devices.add(FakeBleDevice.cadence(id: _deviceId));
    final ble = source(
      _paired(<SensorKind>{SensorKind.speed, SensorKind.cadence}),
    );
    final readings = <SensorReading>[];
    ble.readings.listen(readings.add);
    await ble.start();

    // Two of each: the first packet only sets the counters.
    gateway
      ..wheel(_deviceId, speedMps: 8, circumferenceM: 2.105)
      ..wheel(_deviceId, speedMps: 8, circumferenceM: 2.105)
      ..crank(_deviceId, 85)
      ..crank(_deviceId, 85);
    await pumpEventQueue();

    final speeds = readings.where((r) => r.kind == SensorKind.speed);
    final cadences = readings.where((r) => r.kind == SensorKind.cadence);
    expect(speeds, hasLength(1));
    expect(speeds.single.value, closeTo(8, 0.1));
    expect(cadences, hasLength(1));
    expect(cadences.single.value, closeTo(85, 0.5));
    await ble.dispose();
  });

  test('a power meter reports watts and the cadence it counts', () async {
    gateway.devices.add(FakeBleDevice.power(id: _deviceId));
    final ble = source(
      _paired(<SensorKind>{SensorKind.power, SensorKind.cadence}),
    );
    final readings = <SensorReading>[];
    ble.readings.listen(readings.add);
    await ble.start();

    gateway
      ..watts(_deviceId, 210, cadenceRpm: 90)
      ..watts(_deviceId, 215, cadenceRpm: 90);
    await pumpEventQueue();

    expect(
      readings.where((r) => r.kind == SensorKind.power).map((r) => r.value),
      <double>[210, 215],
    );
    final cadence = readings.where((r) => r.kind == SensorKind.cadence).single;
    expect(cadence.value, closeTo(90, 0.5));
    await ble.dispose();
  });

  test('subscribes to nothing the device does not have', () async {
    // Paired as a strap, but the device only has the power service.
    gateway.devices.add(FakeBleDevice.power(id: _deviceId));
    final ble = source(_paired(<SensorKind>{SensorKind.heartRate}));
    final readings = <SensorReading>[];
    ble.readings.listen(readings.add);
    await ble.start();

    gateway
      ..beat(_deviceId, 150)
      ..watts(_deviceId, 200);
    await pumpEventQueue();

    expect(readings, isEmpty);
    await ble.dispose();
  });

  test('comes back for a device that dropped, and reports again', () {
    fakeAsync((async) {
      gateway.devices.add(FakeBleDevice.strap(id: _deviceId));
      final ble = source(_paired(<SensorKind>{SensorKind.heartRate}));
      final readings = <SensorReading>[];
      ble.readings.listen(readings.add);
      unawaited(ble.start());
      async.flushMicrotasks();
      expect(gateway.connects, <String>[_deviceId]);

      gateway.drop(_deviceId);
      async.flushMicrotasks();
      expect(ble.isConnected, isFalse);

      async.elapse(bleReconnectBackoff.first);
      async.flushMicrotasks();
      expect(gateway.connects, <String>[_deviceId, _deviceId]);
      expect(ble.isConnected, isTrue);

      gateway.beat(_deviceId, 148);
      async.flushMicrotasks();
      expect(readings.single.value, 148);

      unawaited(ble.dispose());
      async.flushTimers();
    });
  });

  test('backs off while the device stays away, and keeps trying', () {
    fakeAsync((async) {
      // Nothing in range at all: every attempt fails.
      final ble = source(_paired(<SensorKind>{SensorKind.heartRate}));
      unawaited(ble.start());
      async.flushMicrotasks();
      expect(gateway.connects, hasLength(1));

      for (final wait in bleReconnectBackoff) {
        final before = gateway.connects.length;
        // A moment short of the wait is still the old count.
        async.elapse(wait - const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(gateway.connects, hasLength(before));
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(gateway.connects, hasLength(before + 1));
      }

      // And then every ten seconds, for as long as it is wanted.
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(gateway.connects, hasLength(bleReconnectBackoff.length + 2));

      unawaited(ble.dispose());
      async.flushTimers();
    });
  });

  test('disposing disconnects and stops trying', () {
    fakeAsync((async) {
      gateway.devices.add(FakeBleDevice.strap(id: _deviceId));
      final ble = BleSensorSource(
        gateway: gateway,
        device: _paired(<SensorKind>{SensorKind.heartRate}),
        wheelCircumferenceM: () => 2.105,
        clock: () => now,
      );
      unawaited(ble.start());
      async.flushMicrotasks();
      expect(gateway.isConnected(_deviceId), isTrue);

      unawaited(ble.dispose());
      async.flushMicrotasks();
      expect(gateway.isConnected(_deviceId), isFalse);

      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(gateway.connects, hasLength(1));
      async.flushTimers();
    });
  });
}
