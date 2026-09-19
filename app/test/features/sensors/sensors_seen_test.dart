import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/sensors/application/sensors_seen.dart';
import 'package:velorki_geo/velorki_geo.dart';

RecordingSnapshot _snapshot(String rideId, {int? heartRateBpm, int? powerW}) =>
    RecordingSnapshot(
      rideId: rideId,
      status: RecordingStatus.active,
      startedAt: DateTime.utc(2026, 9, 19, 8),
      lastPosition: const LatLng(48, 11),
      heartRateBpm: heartRateBpm,
      powerW: powerW,
    );

void main() {
  group('SensorsSeenState', () {
    test('remembers the last reading of each kind through silence', () {
      var seen = const SensorsSeenState();
      seen = seen.absorb(_snapshot('a', heartRateBpm: 140));
      seen = seen.absorb(_snapshot('a', powerW: 210));
      seen = seen.absorb(_snapshot('a'));
      expect(seen.rideId, 'a');
      expect(seen.heartRateBpm, 140);
      expect(seen.powerW, 210);
      expect(seen.cadenceRpm, isNull);
      expect(seen.any, isTrue);
    });

    test('a new ride starts with nothing', () {
      var seen = const SensorsSeenState();
      seen = seen.absorb(_snapshot('a', heartRateBpm: 140));
      seen = seen.absorb(_snapshot('b'));
      expect(seen.rideId, 'b');
      expect(seen.heartRateBpm, isNull);
      expect(seen.any, isFalse);
    });
  });
}
