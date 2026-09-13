import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki_geo/velorki_geo.dart';

geo.Position _fix({
  double accuracy = 0,
  double heading = 0,
  double speed = 0,
  bool flags = false,
}) => geo.Position(
  latitude: 40.8153,
  longitude: -73.9645,
  timestamp: DateTime.utc(2026),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
  hasAccuracy: flags,
  hasHeading: flags,
  hasSpeed: flags,
);

void main() {
  group('MapPosition.measuredValue', () {
    test('takes a flagged value as it stands, zero included', () {
      expect(MapPosition.measuredValue(0, flagged: true), 0);
      expect(MapPosition.measuredValue(12.5, flagged: true), 12.5);
    });

    test('falls back to a non-zero value when the flag is clear', () {
      // geolocator_android drops the has* flags, so an unflagged 28.4° course
      // is still a course.
      expect(MapPosition.measuredValue(28.4, flagged: false), 28.4);
      expect(MapPosition.measuredValue(0, flagged: false), isNull);
    });

    test('rejects a value that is not a number', () {
      expect(MapPosition.measuredValue(double.nan, flagged: true), isNull);
      expect(MapPosition.measuredValue(double.infinity, flagged: true), isNull);
    });
  });

  group('MapPosition.fromGeolocator', () {
    test('keeps accuracy, course and speed an Android fix never flags', () {
      final position = MapPosition.fromGeolocator(
        _fix(accuracy: 5, heading: 28.4, speed: 4.2),
      );

      expect(position.position, const LatLng(40.8153, -73.9645));
      expect(position.accuracyM, 5);
      expect(position.headingDeg, 28.4);
      expect(position.speedMps, 4.2);
    });

    test('reports no course and no speed when nothing measured any', () {
      final position = MapPosition.fromGeolocator(_fix());

      expect(position.accuracyM, 0);
      expect(position.headingDeg, isNull);
      expect(position.speedMps, isNull);
    });

    test('keeps a flagged zero, e.g. a course of due north', () {
      final position = MapPosition.fromGeolocator(
        _fix(accuracy: 5, speed: 3, flags: true),
      );

      expect(position.headingDeg, 0);
    });
  });
}
