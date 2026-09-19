import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/sensors/data/ble_gateway.dart';
import 'package:velorki/features/sensors/domain/ble_profiles.dart';

void main() {
  group('short uuids', () {
    test('a registry uuid comes back as its 16-bit number', () {
      expect(shortBleUuid('0000180d-0000-1000-8000-00805f9b34fb'), '180d');
      expect(shortBleUuid('00002a37-0000-1000-8000-00805F9B34FB'), '2a37');
    });

    test('the three profiles survive the round trip', () {
      for (final uuid in <String>[
        heartRateServiceUuid,
        heartRateMeasurementUuid,
        cyclingSpeedCadenceServiceUuid,
        cscMeasurementUuid,
        cyclingPowerServiceUuid,
        cyclingPowerMeasurementUuid,
      ]) {
        expect(
          shortBleUuid('0000$uuid-0000-1000-8000-00805f9b34fb'),
          uuid,
          reason: 'the constants are what a discovered uuid shortens to',
        );
      }
    });

    test('a manufacturer uuid is kept whole', () {
      const String custom = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
      expect(shortBleUuid(custom), custom);
      expect(shortBleUuid(custom.toUpperCase()), custom);
    });

    test('anything that is not a uuid at all is left alone', () {
      expect(shortBleUuid('180d'), '180d');
      expect(shortBleUuid(''), '');
    });
  });

  group('supported platforms', () {
    test('the phones have a radio', () {
      expect(bleSupportedOn(TargetPlatform.iOS), isTrue);
      expect(bleSupportedOn(TargetPlatform.android), isTrue);
    });

    test('the desktop builds are left without one', () {
      expect(bleSupportedOn(TargetPlatform.macOS), isFalse);
      expect(bleSupportedOn(TargetPlatform.linux), isFalse);
      expect(bleSupportedOn(TargetPlatform.windows), isFalse);
    });
  });
}
