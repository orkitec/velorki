import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/sensors/data/paired_sensors.dart';
import 'package:velorki/features/sensors/data/sensor_settings.dart';
import 'package:velorki/features/sensors/domain/ble_profiles.dart';
import 'package:velorki/features/sensors/domain/sensor_reading.dart';

const PairedSensor _strap = PairedSensor(
  id: 'aa:bb',
  name: 'Strap',
  kinds: <SensorKind>{SensorKind.heartRate},
);

const PairedSensor _meter = PairedSensor(
  id: 'cc:dd',
  name: 'Meter',
  kinds: <SensorKind>{SensorKind.power, SensorKind.cadence},
);

void main() {
  late SharedPreferences prefs;

  Future<ProviderContainer> containerWith([
    Map<String, Object> initial = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('an app that has never paired anything holds nothing', () async {
    final container = await containerWith();
    expect(container.read(pairedSensorsProvider), isEmpty);
    expect(prefs.getString(prefsPairedSensors), isNull);
  });

  test('pairing writes the id, the name and the kinds', () async {
    final container = await containerWith();
    await container.read(pairedSensorsProvider.notifier).pair(_strap);

    expect(container.read(pairedSensorsProvider), <PairedSensor>[_strap]);
    expect(jsonDecode(prefs.getString(prefsPairedSensors)!), <Object>[
      <String, Object>{
        'id': 'aa:bb',
        'name': 'Strap',
        'kinds': <String>['heartRate'],
      },
    ]);
  });

  test(
    'pairing the same device again replaces it rather than doubling it',
    () async {
      final container = await containerWith();
      final notifier = container.read(pairedSensorsProvider.notifier);
      await notifier.pair(_strap);
      await notifier.pair(
        _strap.copyWith(
          name: 'Chest',
          kinds: <SensorKind>{SensorKind.heartRate},
        ),
      );

      expect(container.read(pairedSensorsProvider), hasLength(1));
      expect(container.read(pairedSensorsProvider).single.name, 'Chest');
    },
  );

  test('forgetting the last device removes the key altogether', () async {
    final container = await containerWith();
    final notifier = container.read(pairedSensorsProvider.notifier);
    await notifier.pair(_strap);
    await notifier.pair(_meter);
    await notifier.forget(_strap.id);

    expect(container.read(pairedSensorsProvider), <PairedSensor>[_meter]);
    await notifier.forget(_meter.id);
    expect(container.read(pairedSensorsProvider), isEmpty);
    expect(prefs.getString(prefsPairedSensors), isNull);
  });

  test('renaming keeps the id and the kinds', () async {
    final container = await containerWith();
    final notifier = container.read(pairedSensorsProvider.notifier);
    await notifier.pair(_meter);
    await notifier.rename(_meter.id, 'Left crank');

    final paired = container.read(pairedSensorsProvider).single;
    expect(paired.id, _meter.id);
    expect(paired.name, 'Left crank');
    expect(paired.kinds, _meter.kinds);
  });

  test(
    'reads what an earlier run stored, and skips what it cannot read',
    () async {
      final container = await containerWith(<String, Object>{
        prefsPairedSensors: jsonEncode(<Object>[
          <String, Object>{
            'id': 'aa:bb',
            'name': 'Strap',
            'kinds': <String>['heartRate'],
          },
          <String, Object>{'name': 'no id at all'},
          'not a device',
          <String, Object>{
            'id': 'ee:ff',
            'name': 'Wheel',
            'kinds': <String>['speed', 'invented'],
          },
        ]),
      });

      expect(container.read(pairedSensorsProvider), <PairedSensor>[
        _strap,
        const PairedSensor(
          id: 'ee:ff',
          name: 'Wheel',
          kinds: <SensorKind>{SensorKind.speed},
        ),
      ]);
    },
  );

  test(
    'preferences that are not a list at all leave the rider with nothing',
    () async {
      final container = await containerWith(<String, Object>{
        prefsPairedSensors: 'not json',
      });
      expect(container.read(pairedSensorsProvider), isEmpty);
    },
  );

  group('wheel circumference', () {
    test('defaults to a 700x25c wheel and stores nothing', () async {
      final container = await containerWith();
      expect(
        container.read(sensorSettingsProvider).wheelCircumferenceMm,
        defaultWheelCircumferenceMm,
      );
      expect(container.read(sensorSettingsProvider).wheelCircumferenceM, 2.105);
      expect(prefs.getInt(prefsWheelCircumferenceMm), isNull);
    });

    test(
      'is written when the rider changes it, and removed when it goes back',
      () async {
        final container = await containerWith();
        final notifier = container.read(sensorSettingsProvider.notifier);
        await notifier.setWheelCircumferenceMm(2326);

        expect(
          container.read(sensorSettingsProvider).wheelCircumferenceMm,
          2326,
        );
        expect(prefs.getInt(prefsWheelCircumferenceMm), 2326);

        await notifier.setWheelCircumferenceMm(defaultWheelCircumferenceMm);
        expect(prefs.getInt(prefsWheelCircumferenceMm), isNull);
      },
    );

    test('is clamped to something a bicycle could have', () async {
      final container = await containerWith();
      final notifier = container.read(sensorSettingsProvider.notifier);

      await notifier.setWheelCircumferenceMm(10);
      expect(
        container.read(sensorSettingsProvider).wheelCircumferenceMm,
        minWheelCircumferenceMm,
      );

      await notifier.setWheelCircumferenceMm(99999);
      expect(
        container.read(sensorSettingsProvider).wheelCircumferenceMm,
        maxWheelCircumferenceMm,
      );
    });
  });
}
