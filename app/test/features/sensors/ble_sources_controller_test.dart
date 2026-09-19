import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/sensors/application/ble_sources_controller.dart';
import 'package:velorki/features/sensors/application/sensor_hub.dart';
import 'package:velorki/features/sensors/data/ble_gateway.dart';
import 'package:velorki/features/sensors/data/ble_sensor_source.dart';
import 'package:velorki/features/sensors/data/paired_sensors.dart';
import 'package:velorki/features/sensors/domain/sensor_reading.dart';
import 'package:velorki/features/sensors/testing/fake_ble_gateway.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../recording/support/fakes.dart';

const String _strapId = 'aa:bb';

/// The rider has one strap paired, as an earlier run left it.
String _stored() => jsonEncode(<Object>[
  <String, Object>{
    'id': _strapId,
    'name': 'Strap',
    'kinds': <String>['heartRate'],
  },
]);

RecordingSnapshot _snapshot({required RecordingStatus status}) =>
    RecordingSnapshot(
      rideId: 'ride-1',
      status: status,
      startedAt: DateTime.utc(2026, 9, 18, 9),
      distanceM: 1200,
      elapsed: const Duration(minutes: 5),
      moving: const Duration(minutes: 5),
      speedMps: 6,
      avgSpeedMps: 5,
      lastPosition: const LatLng(48.1, 11.2),
      pointCount: 30,
    );

void main() {
  late FakeRecordingService service;
  late FakeBleGateway gateway;

  Future<ProviderContainer> containerWith({
    bool paired = true,
    bool hasRadio = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (paired) prefsPairedSensors: _stored(),
    });
    final prefs = await SharedPreferences.getInstance();
    service = FakeRecordingService();
    addTearDown(service.dispose);
    gateway = FakeBleGateway(
      devices: <FakeBleDevice>[FakeBleDevice.strap(id: _strapId)],
    );
    addTearDown(gateway.dispose);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        recordingServiceProvider.overrideWithValue(service),
        bleGatewayProvider.overrideWithValue(hasRadio ? gateway : null),
      ],
    );
    addTearDown(container.dispose);
    container.read(bleSourcesProvider);
    await container.read(bleSourcesProvider.notifier).settled;
    return container;
  }

  Future<void> settle(ProviderContainer container) async {
    await pumpEventQueue();
    await container.read(bleSourcesProvider.notifier).settled;
  }

  Iterable<String> registered(ProviderContainer container) =>
      container.read(sensorHubProvider.notifier).sources.map((s) => s.id);

  test(
    'connects nothing while no ride records and no screen is open',
    () async {
      final container = await containerWith();
      expect(gateway.connects, isEmpty);
      expect(registered(container), isEmpty);
      expect(container.read(bleSourcesProvider), isEmpty);
    },
  );

  test('connects while a ride records, and lets go when it ends', () async {
    final container = await containerWith();

    service.emit(_snapshot(status: RecordingStatus.active));
    await settle(container);
    expect(gateway.connects, <String>[_strapId]);
    expect(registered(container), <String>[bleSensorSourceId(_strapId)]);
    expect(
      container.read(bleSourcesProvider)[_strapId],
      BleLinkStatus.connected,
    );

    service.emit(_snapshot(status: RecordingStatus.idle));
    await settle(container);
    expect(gateway.isConnected(_strapId), isFalse);
    expect(registered(container), isEmpty);
    expect(container.read(bleSourcesProvider), isEmpty);
  });

  test('connects while the sensors screen holds it open', () async {
    final container = await containerWith();

    container.read(bleLiveProvider).acquire();
    await settle(container);
    expect(registered(container), <String>[bleSensorSourceId(_strapId)]);

    container.read(bleLiveProvider).release();
    await settle(container);
    expect(registered(container), isEmpty);
  });

  test('a second holder keeps it open until both let go', () async {
    final container = await containerWith();
    final live = container.read(bleLiveProvider)
      ..acquire()
      ..acquire();
    await settle(container);
    expect(live.isLive, isTrue);

    live.release();
    await settle(container);
    expect(live.isLive, isTrue);
    expect(registered(container), hasLength(1));

    live.release();
    await settle(container);
    expect(live.isLive, isFalse);
    expect(registered(container), isEmpty);
  });

  test('with nothing paired it never reaches the radio', () async {
    final container = await containerWith(paired: false);
    container.read(bleLiveProvider).acquire();
    service.emit(_snapshot(status: RecordingStatus.active));
    await settle(container);

    expect(gateway.connects, isEmpty);
    expect(registered(container), isEmpty);
  });

  test('on a platform with no radio it does nothing at all', () async {
    final container = await containerWith(hasRadio: false);
    container.read(bleLiveProvider).acquire();
    await settle(container);
    expect(registered(container), isEmpty);
  });

  test(
    'a device forgotten mid-ride is disconnected and unregistered',
    () async {
      final container = await containerWith();
      service.emit(_snapshot(status: RecordingStatus.active));
      await settle(container);
      expect(registered(container), hasLength(1));

      await container.read(pairedSensorsProvider.notifier).forget(_strapId);
      await settle(container);

      expect(gateway.isConnected(_strapId), isFalse);
      expect(registered(container), isEmpty);
    },
  );

  test(
    'a device paired mid-ride is connected without touching the others',
    () async {
      final container = await containerWith();
      gateway.devices.add(FakeBleDevice.power(id: 'cc:dd'));
      service.emit(_snapshot(status: RecordingStatus.active));
      await settle(container);

      await container
          .read(pairedSensorsProvider.notifier)
          .pair(
            const PairedSensor(
              id: 'cc:dd',
              name: 'Meter',
              kinds: <SensorKind>{SensorKind.power, SensorKind.cadence},
            ),
          );
      await settle(container);

      expect(gateway.connects, <String>[_strapId, 'cc:dd']);
      expect(registered(container), <String>[
        bleSensorSourceId(_strapId),
        bleSensorSourceId('cc:dd'),
      ]);
    },
  );

  test('renaming a device leaves its connection alone', () async {
    final container = await containerWith();
    service.emit(_snapshot(status: RecordingStatus.active));
    await settle(container);

    await container
        .read(pairedSensorsProvider.notifier)
        .rename(_strapId, 'Chest');
    await settle(container);

    expect(gateway.connects, <String>[_strapId], reason: 'not reconnected');
    expect(registered(container), hasLength(1));
  });

  test('what a connected sensor reports reaches the hub', () async {
    final container = await containerWith();
    service.emit(_snapshot(status: RecordingStatus.active));
    await settle(container);

    gateway.beat(_strapId, 151);
    await pumpEventQueue();

    expect(container.read(sensorHubProvider).heartRateBpm, 151);
  });
}
