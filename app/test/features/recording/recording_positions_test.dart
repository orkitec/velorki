import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/features/recording/data/recording_positions.dart';

geo.Position _fix({
  required bool flagged,
  double altitude = 123.4,
  double speed = 4.2,
  double accuracy = 6,
}) => geo.Position(
  latitude: 48,
  longitude: 11,
  timestamp: DateTime.utc(2026, 9, 13, 12),
  accuracy: accuracy,
  altitude: altitude,
  altitudeAccuracy: 3,
  heading: 90,
  headingAccuracy: 5,
  speed: speed,
  speedAccuracy: 1,
  hasAccuracy: flagged,
  hasAltitude: flagged,
  hasHeading: flagged,
  hasSpeed: flagged,
);

void main() {
  group('trackPointFromPosition', () {
    test('keeps the measured fields when the platform flags them', () {
      final point = trackPointFromPosition(_fix(flagged: true));
      expect(point.ele, 123.4);
      expect(point.speedMps, 4.2);
      expect(point.accuracyM, 6);
      // The course rides along so the record screen can turn the map with
      // the rider; it is not written to the journal.
      expect(point.headingDeg, 90);
    });

    test('keeps non-zero fields even when Android drops the flags', () {
      // geolocator_android rebuilds a Position without its has* flags; an
      // altitude of 123.4 m is a measurement all the same, and without it a
      // whole ride climbed nothing.
      final point = trackPointFromPosition(_fix(flagged: false));
      expect(point.ele, 123.4);
      expect(point.speedMps, 4.2);
      expect(point.accuracyM, 6);
    });

    test('an unflagged zero is treated as not measured', () {
      final point = trackPointFromPosition(
        _fix(flagged: false, altitude: 0, speed: 0, accuracy: 0),
      );
      expect(point.ele, isNull);
      expect(point.speedMps, isNull);
      expect(point.accuracyM, isNull);
    });
  });
}
