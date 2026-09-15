import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter/foundation.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/recording/data/recording_positions.dart';
import 'package:velorki/features/recording/domain/gps_precision.dart';

geo.Position _fix({
  required bool flagged,
  double altitude = 123.4,
  double speed = 4.2,
  double accuracy = 6,
  double heading = 90,
}) => geo.Position(
  latitude: 48,
  longitude: 11,
  timestamp: DateTime.utc(2026, 9, 13, 12),
  accuracy: accuracy,
  altitude: altitude,
  altitudeAccuracy: 3,
  heading: heading,
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

    test('an iPhone with no course and no speed sends -1 for both', () {
      // Core Location flags the fix as having them all the same, so nothing
      // but the value itself says they are missing.
      final point = trackPointFromPosition(
        _fix(flagged: true, speed: -1, heading: -1),
      );
      expect(point.speedMps, isNull);
      expect(point.headingDeg, isNull);
    });

    test('a course of 360 is written as due north', () {
      final point = trackPointFromPosition(_fix(flagged: true, heading: 360));
      expect(point.headingDeg, 0);
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

  group('recordingLocationSettings', () {
    geo.LocationSettings android(GpsPrecision precision) =>
        recordingLocationSettings(
          platform: TargetPlatform.android,
          precision: precision,
        );

    test('precise asks the phone for the best fix it has, every second', () {
      final settings = android(GpsPrecision.precise) as geo.AndroidSettings;

      expect(settings.accuracy, geo.LocationAccuracy.best);
      expect(settings.distanceFilter, 5);
      expect(settings.intervalDuration, const Duration(seconds: 1));
    });

    test('normal keeps the rhythm at the ordinary high accuracy', () {
      final settings = android(GpsPrecision.normal) as geo.AndroidSettings;

      expect(settings.accuracy, geo.LocationAccuracy.high);
      expect(settings.distanceFilter, 5);
      expect(settings.intervalDuration, const Duration(seconds: 1));
    });

    test('saver halves the duty cycle: ten metres, two seconds', () {
      final settings = android(GpsPrecision.saver) as geo.AndroidSettings;

      expect(settings.accuracy, geo.LocationAccuracy.high);
      expect(settings.distanceFilter, 10);
      expect(settings.intervalDuration, const Duration(seconds: 2));
    });

    test('an iPhone keeps recording in the background at every profile', () {
      final settings = recordingLocationSettings(
        platform: TargetPlatform.iOS,
        precision: GpsPrecision.saver,
      ) as geo.AppleSettings;

      expect(settings.accuracy, geo.LocationAccuracy.high);
      expect(settings.distanceFilter, 10);
      expect(settings.allowBackgroundLocationUpdates, isTrue);
      expect(settings.pauseLocationUpdatesAutomatically, isFalse);
    });

    test('the desktop builds get the plain settings', () {
      final settings = recordingLocationSettings(
        platform: TargetPlatform.linux,
        precision: GpsPrecision.precise,
      );

      expect(settings.accuracy, geo.LocationAccuracy.best);
      expect(settings.distanceFilter, 5);
    });

    test('nothing said means normal', () {
      final settings = recordingLocationSettings(
        platform: TargetPlatform.android,
      );

      expect(settings.accuracy, geo.LocationAccuracy.high);
      expect(settings.distanceFilter, 5);
    });
  });

  group('recordingFixes', () {
    test('subscribes with the profile it was given', () {
      final source = _RecordingSource();

      recordingFixes(
        source,
        platform: TargetPlatform.android,
        precision: GpsPrecision.saver,
      ).listen(null).cancel();

      expect(source.settings.single.distanceFilter, 10);
    });
  });
}

/// A position source that only notes what it was subscribed with.
class _RecordingSource implements PositionSource {
  final List<geo.LocationSettings> settings = <geo.LocationSettings>[];

  @override
  Stream<geo.Position> positions(geo.LocationSettings locationSettings) {
    settings.add(locationSettings);
    return const Stream<geo.Position>.empty();
  }

  @override
  Future<geo.Position?> lastKnown() async => null;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) async => null;
}
