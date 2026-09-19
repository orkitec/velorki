import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/sensors/domain/ble_profiles.dart';
import 'package:velorki/features/sensors/domain/sensor_reading.dart';

/// A CSC packet with wheel data only.
List<int> _wheel(int revolutions, int eventTime) => <int>[
  0x01,
  ..._le32(revolutions),
  ..._le16(eventTime),
];

/// A CSC packet with crank data only.
List<int> _crank(int revolutions, int eventTime) => <int>[
  0x02,
  ..._le16(revolutions),
  ..._le16(eventTime),
];

List<int> _le16(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _le32(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

/// Ticks of the 1/1024 s clock in [seconds].
int _ticks(double seconds) => (seconds * 1024).round();

void main() {
  final at = DateTime.utc(2026, 9, 18, 9);

  group('heart rate measurement', () {
    test('reads an 8-bit rate', () {
      expect(parseHeartRateMeasurement(<int>[0x00, 62]), 62);
      expect(parseHeartRateMeasurement(<int>[0x00, 255]), 255);
    });

    test('reads a 16-bit rate when flags bit 0 is set', () {
      expect(parseHeartRateMeasurement(<int>[0x01, 0x2C, 0x01]), 300);
    });

    test('ignores the energy and RR fields that follow', () {
      // Flags: 16-bit rate, energy expended present, RR intervals present.
      expect(
        parseHeartRateMeasurement(<int>[
          0x19,
          0x96,
          0x00,
          0x40,
          0x06,
          0x01,
          0x02,
        ]),
        150,
      );
    });

    test('ignores the sensor contact bits', () {
      // Contact supported and not detected: still a heart rate.
      expect(parseHeartRateMeasurement(<int>[0x04, 88]), 88);
      expect(parseHeartRateMeasurement(<int>[0x06, 88]), 88);
    });

    test('refuses a packet shorter than its flags promise', () {
      expect(parseHeartRateMeasurement(const <int>[]), isNull);
      expect(parseHeartRateMeasurement(<int>[0x00]), isNull);
      expect(parseHeartRateMeasurement(<int>[0x01, 0x96]), isNull);
    });
  });

  group('csc measurement', () {
    test('reads wheel data', () {
      final measurement = parseCscMeasurement(_wheel(1000, 2048))!;
      expect(measurement.wheelRevolutions, 1000);
      expect(measurement.wheelEventTime, 2048);
      expect(measurement.hasCrank, isFalse);
    });

    test('reads crank data', () {
      final measurement = parseCscMeasurement(_crank(40, 512))!;
      expect(measurement.crankRevolutions, 40);
      expect(measurement.crankEventTime, 512);
      expect(measurement.hasWheel, isFalse);
    });

    test('reads both, crank after wheel', () {
      final measurement = parseCscMeasurement(<int>[
        0x03,
        ..._le32(7),
        ..._le16(1024),
        ..._le16(3),
        ..._le16(2048),
      ])!;
      expect(measurement.wheelRevolutions, 7);
      expect(measurement.wheelEventTime, 1024);
      expect(measurement.crankRevolutions, 3);
      expect(measurement.crankEventTime, 2048);
    });

    test('refuses an empty packet, one with no flags set, and a short one', () {
      expect(parseCscMeasurement(const <int>[]), isNull);
      expect(parseCscMeasurement(<int>[0x00]), isNull);
      expect(parseCscMeasurement(<int>[0x01, 1, 2, 3]), isNull);
      expect(
        parseCscMeasurement(<int>[0x03, ..._le32(7), ..._le16(1024), 1]),
        isNull,
      );
    });
  });

  group('csc tracker', () {
    test('has nothing to say about the first packet', () {
      expect(
        CscTracker().add(_wheel(10, 1024), at: at, wheelCircumferenceM: 2.105),
        isNull,
      );
    });

    test('derives a speed from one wheel turn a second', () {
      final tracker = CscTracker()
        ..add(_wheel(10, 1024), at: at, wheelCircumferenceM: 2.105);
      final update = tracker.add(
        _wheel(11, 2048),
        at: at.add(const Duration(seconds: 1)),
        wheelCircumferenceM: 2.105,
      )!;
      expect(update.speedMps, closeTo(2.105, 0.001));
      expect(update.cadenceRpm, isNull);
    });

    test('follows the wheel circumference it is given', () {
      final tracker = CscTracker()
        ..add(_wheel(10, 0), at: at, wheelCircumferenceM: 2.2);
      final update = tracker.add(
        _wheel(12, _ticks(1)),
        at: at.add(const Duration(seconds: 1)),
        wheelCircumferenceM: 2.2,
      )!;
      expect(update.speedMps, closeTo(4.4, 0.001));
    });

    test('takes the event time over the wrap at 64 s', () {
      final tracker = CscTracker()
        ..add(_wheel(10, 65024), at: at, wheelCircumferenceM: 2.0);
      // 65024 + 1024 ticks is one second later, and 512 past the wrap.
      final update = tracker.add(
        _wheel(11, 512),
        at: at.add(const Duration(seconds: 1)),
        wheelCircumferenceM: 2.0,
      )!;
      expect(update.speedMps, closeTo(2.0, 0.001));
    });

    test('takes the wheel revolutions over the 32-bit wrap', () {
      final tracker = CscTracker()
        ..add(_wheel(0xFFFFFFFE, 0), at: at, wheelCircumferenceM: 2.0);
      final update = tracker.add(
        _wheel(1, _ticks(1)),
        at: at.add(const Duration(seconds: 1)),
        wheelCircumferenceM: 2.0,
      )!;
      expect(update.speedMps, closeTo(6.0, 0.001), reason: 'three turns');
    });

    test('derives a cadence from the crank counters', () {
      final tracker = CscTracker()
        ..add(_crank(40, 0), at: at, wheelCircumferenceM: 2.105);
      final update = tracker.add(
        _crank(41, _ticks(60 / 85)),
        at: at.add(const Duration(seconds: 1)),
        wheelCircumferenceM: 2.105,
      )!;
      expect(update.cadenceRpm, closeTo(85, 0.1));
      expect(update.speedMps, isNull);
    });

    test('takes the crank revolutions over the 16-bit wrap', () {
      final tracker = CscTracker()
        ..add(_crank(0xFFFF, 0), at: at, wheelCircumferenceM: 2.105);
      final update = tracker.add(
        _crank(1, _ticks(1)),
        at: at.add(const Duration(seconds: 1)),
        wheelCircumferenceM: 2.105,
      )!;
      expect(update.cadenceRpm, closeTo(120, 0.1), reason: 'two turns');
    });

    test('says nothing while the event time stands still', () {
      final tracker = CscTracker()
        ..add(_crank(40, 512), at: at, wheelCircumferenceM: 2.105);
      expect(
        tracker.add(
          _crank(40, 512),
          at: at.add(const Duration(seconds: 1)),
          wheelCircumferenceM: 2.105,
        ),
        isNull,
      );
    });

    test('reports a standing wheel as zero once, then falls silent', () {
      final tracker = CscTracker()
        ..add(_wheel(10, 1024), at: at, wheelCircumferenceM: 2.105);
      // Still turning.
      expect(
        tracker
            .add(
              _wheel(11, 2048),
              at: at.add(const Duration(seconds: 1)),
              wheelCircumferenceM: 2.105,
            )!
            .speedMps,
        closeTo(2.105, 0.001),
      );
      // Stopped, but not for long enough yet.
      expect(
        tracker.add(
          _wheel(11, 2048),
          at: at.add(const Duration(seconds: 3)),
          wheelCircumferenceM: 2.105,
        ),
        isNull,
      );
      expect(
        tracker
            .add(
              _wheel(11, 2048),
              at: at.add(const Duration(seconds: 5)),
              wheelCircumferenceM: 2.105,
            )!
            .speedMps,
        0,
      );
      // And then nothing more, however long it stands there.
      expect(
        tracker.add(
          _wheel(11, 2048),
          at: at.add(const Duration(seconds: 20)),
          wheelCircumferenceM: 2.105,
        ),
        isNull,
      );
    });

    test('a wheel that turns again is reported again', () {
      final tracker = CscTracker()
        ..add(_wheel(10, 1024), at: at, wheelCircumferenceM: 2.0)
        ..add(
          _wheel(10, 1024),
          at: at.add(const Duration(seconds: 5)),
          wheelCircumferenceM: 2.0,
        );
      final moving = tracker.add(
        _wheel(11, 1024 + _ticks(1)),
        at: at.add(const Duration(seconds: 6)),
        wheelCircumferenceM: 2.0,
      )!;
      expect(moving.speedMps, closeTo(2.0, 0.001));
    });

    test('refuses an unreadable packet', () {
      expect(
        CscTracker().add(<int>[0x01, 1], at: at, wheelCircumferenceM: 2.105),
        isNull,
      );
    });
  });

  group('cycling power measurement', () {
    test('reads the watts out of a bare packet', () {
      final measurement = parseCyclingPowerMeasurement(<int>[
        ..._le16(0),
        ..._le16(210),
      ])!;
      expect(measurement.powerW, 210);
      expect(measurement.crankRevolutions, isNull);
    });

    test('reads negative watts as the signed value they are', () {
      final measurement = parseCyclingPowerMeasurement(<int>[
        ..._le16(0),
        0xF6,
        0xFF,
      ])!;
      expect(measurement.powerW, -10);
    });

    test('reads the crank counters right after the watts', () {
      final measurement = parseCyclingPowerMeasurement(<int>[
        ..._le16(0x20),
        ..._le16(180),
        ..._le16(12),
        ..._le16(1024),
      ])!;
      expect(measurement.crankRevolutions, 12);
      expect(measurement.crankEventTime, 1024);
    });

    test('walks past the optional fields that precede the crank data', () {
      // Pedal power balance (bit 0, one byte), accumulated torque (bit 2, two
      // bytes), wheel revolution data (bit 4, six bytes), then the crank.
      final measurement = parseCyclingPowerMeasurement(<int>[
        ..._le16(0x01 | 0x04 | 0x10 | 0x20),
        ..._le16(240),
        50,
        ..._le16(900),
        ..._le32(4000),
        ..._le16(2048),
        ..._le16(77),
        ..._le16(1536),
      ])!;
      expect(measurement.powerW, 240);
      expect(measurement.crankRevolutions, 77);
      expect(measurement.crankEventTime, 1536);
    });

    test('refuses a packet too short for its flags', () {
      expect(parseCyclingPowerMeasurement(<int>[0x00, 0x00, 0x01]), isNull);
      expect(
        parseCyclingPowerMeasurement(<int>[..._le16(0x20), ..._le16(100), 1]),
        isNull,
      );
    });
  });

  group('cycling power tracker', () {
    test('reports the watts of the first packet and no cadence', () {
      final update = CyclingPowerTracker().add(<int>[
        ..._le16(0x20),
        ..._le16(210),
        ..._le16(12),
        ..._le16(0),
      ])!;
      expect(update.powerW, 210);
      expect(update.cadenceRpm, isNull);
    });

    test('derives a cadence from two crank counters', () {
      final tracker = CyclingPowerTracker()
        ..add(<int>[..._le16(0x20), ..._le16(210), ..._le16(12), ..._le16(0)]);
      final update = tracker.add(<int>[
        ..._le16(0x20),
        ..._le16(215),
        ..._le16(13),
        ..._le16(_ticks(60 / 90)),
      ])!;
      expect(update.powerW, 215);
      expect(update.cadenceRpm, closeTo(90, 0.1));
    });

    test('says nothing about cadence while the crank stands still', () {
      final tracker = CyclingPowerTracker()
        ..add(<int>[..._le16(0x20), ..._le16(0), ..._le16(12), ..._le16(512)]);
      final update = tracker.add(<int>[
        ..._le16(0x20),
        ..._le16(0),
        ..._le16(12),
        ..._le16(512),
      ])!;
      expect(update.powerW, 0);
      expect(update.cadenceRpm, isNull);
    });
  });

  group('kinds for services', () {
    test('a strap measures a heart rate', () {
      expect(bleKindsForServices(<String>{heartRateServiceUuid}), <SensorKind>{
        SensorKind.heartRate,
      });
    });

    test('a speed and cadence sensor may be either half', () {
      expect(
        bleKindsForServices(<String>{cyclingSpeedCadenceServiceUuid}),
        <SensorKind>{SensorKind.speed, SensorKind.cadence},
      );
    });

    test('a power meter counts its crank too', () {
      expect(
        bleKindsForServices(<String>{cyclingPowerServiceUuid}),
        <SensorKind>{SensorKind.power, SensorKind.cadence},
      );
    });

    test('a service Velorki does not read measures nothing', () {
      expect(bleKindsForServices(<String>{'180f'}), isEmpty);
    });
  });
}
