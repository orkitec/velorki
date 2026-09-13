import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/ride_stats.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki_geo/velorki_geo.dart';

RecordingSnapshot _snapshot({
  RecordingStatus status = RecordingStatus.active,
  bool autoPaused = false,
  LatLng? lastPosition = const LatLng(48.1374, 11.5755),
  double? accuracyM = 4.5,
  double? headingDeg = 91.5,
  List<LatLng> newPoints = const <LatLng>[
    LatLng(48.1374, 11.5755),
    LatLng(48.1375, 11.5756),
  ],
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: status,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: autoPaused,
  distanceM: 1234.5,
  elapsed: const Duration(minutes: 12, seconds: 30),
  moving: const Duration(minutes: 11),
  speedMps: 5.5,
  avgSpeedMps: 4.25,
  maxSpeedMps: 9.75,
  ascentM: 120.5,
  descentM: 80.25,
  lastPosition: lastPosition,
  accuracyM: accuracyM,
  headingDeg: headingDeg,
  pointCount: 750,
  newPoints: newPoints,
);

void main() {
  group('RecordingStatus', () {
    test('reads back every name it writes', () {
      for (final status in RecordingStatus.values) {
        expect(RecordingStatus.fromName(status.name), status);
      }
    });

    test('a missing or unknown status is read as an active ride', () {
      // A corrupt recording_state.json must never lose a ride, so anything
      // unreadable is treated as a recording that is still running.
      expect(RecordingStatus.fromName(null), RecordingStatus.active);
      expect(RecordingStatus.fromName(''), RecordingStatus.active);
      expect(RecordingStatus.fromName('Paused'), RecordingStatus.active);
      expect(RecordingStatus.fromName('stopped'), RecordingStatus.active);
    });

    test('idle is the only status that is not a recording', () {
      expect(RecordingStatus.idle.isRecording, isFalse);
      expect(RecordingStatus.active.isRecording, isTrue);
      expect(RecordingStatus.paused.isRecording, isTrue);
    });
  });

  group('RecordingSnapshot', () {
    test('a fresh snapshot starts at zero', () {
      final snapshot = RecordingSnapshot(
        rideId: 'ride-1',
        status: RecordingStatus.active,
        startedAt: DateTime.utc(2026, 9, 12, 10),
      );

      expect(snapshot.autoPaused, isFalse);
      expect(snapshot.distanceM, 0);
      expect(snapshot.elapsed, Duration.zero);
      expect(snapshot.moving, Duration.zero);
      expect(snapshot.speedMps, 0);
      expect(snapshot.avgSpeedMps, 0);
      expect(snapshot.maxSpeedMps, 0);
      expect(snapshot.ascentM, 0);
      expect(snapshot.descentM, 0);
      expect(snapshot.lastPosition, isNull);
      expect(snapshot.accuracyM, isNull);
      expect(snapshot.headingDeg, isNull);
      expect(snapshot.pointCount, 0);
      expect(snapshot.newPoints, isEmpty);
    });

    test('a pause the rider pressed is told from an auto pause', () {
      expect(
        _snapshot(status: RecordingStatus.paused).isManuallyPaused,
        isTrue,
      );
      expect(
        _snapshot(
          status: RecordingStatus.paused,
          autoPaused: true,
        ).isManuallyPaused,
        isFalse,
      );
      // Standing still while active is not a pause at all.
      expect(_snapshot(autoPaused: true).isManuallyPaused, isFalse);
    });

    test('toString names the ride, status, distance and points', () {
      expect(
        _snapshot().toString(),
        'RecordingSnapshot(ride-1, active, 1235 m, 0:12:30.000000, '
        '750 points)',
      );
    });
  });

  group('RecordingSnapshot.toMap', () {
    test('every message says what kind it is', () {
      expect(
        _snapshot().toMap()[recordingMessageKind],
        recordingSnapshotMessage,
      );
    });

    test('the new points travel as a flat list of coordinates', () {
      // One list of doubles instead of a list of maps: this crosses the
      // isolate boundary every second.
      expect(_snapshot().toMap()['newPoints'], <double>[
        48.1374,
        11.5755,
        48.1375,
        11.5756,
      ]);
    });

    test('durations travel as whole milliseconds', () {
      final map = _snapshot().toMap();

      expect(
        map['elapsedMs'],
        const Duration(minutes: 12, seconds: 30).inMilliseconds,
      );
      expect(map['movingMs'], const Duration(minutes: 11).inMilliseconds);
    });

    test('the start is sent as UTC milliseconds', () {
      final local = RecordingSnapshot(
        rideId: 'ride-1',
        status: RecordingStatus.active,
        startedAt: DateTime.utc(2026, 9, 12, 10).toLocal(),
      );

      expect(
        local.toMap()['startedAt'],
        DateTime.utc(2026, 9, 12, 10).millisecondsSinceEpoch,
      );
    });

    test('fields the recorder has no value for are left out', () {
      final map = _snapshot(
        lastPosition: null,
        accuracyM: null,
        headingDeg: null,
      ).toMap();

      expect(map.containsKey('lat'), isFalse);
      expect(map.containsKey('lon'), isFalse);
      expect(map.containsKey('accuracyM'), isFalse);
      expect(map.containsKey('headingDeg'), isFalse);
    });
  });

  group('RecordingSnapshot.fromMap', () {
    test('a full snapshot survives the trip to the UI isolate', () {
      final original = _snapshot(
        status: RecordingStatus.paused,
        autoPaused: true,
      );

      final copy = RecordingSnapshot.fromMap(original.toMap());

      expect(copy.rideId, original.rideId);
      expect(copy.status, RecordingStatus.paused);
      expect(copy.startedAt, original.startedAt);
      expect(copy.autoPaused, isTrue);
      expect(copy.distanceM, original.distanceM);
      expect(copy.elapsed, original.elapsed);
      expect(copy.moving, original.moving);
      expect(copy.speedMps, original.speedMps);
      expect(copy.avgSpeedMps, original.avgSpeedMps);
      expect(copy.maxSpeedMps, original.maxSpeedMps);
      expect(copy.ascentM, original.ascentM);
      expect(copy.descentM, original.descentM);
      expect(copy.lastPosition, original.lastPosition);
      expect(copy.accuracyM, original.accuracyM);
      expect(copy.headingDeg, original.headingDeg);
      expect(copy.pointCount, original.pointCount);
      expect(copy.newPoints, original.newPoints);
    });

    test('the flattened coordinates become points again', () {
      final copy = RecordingSnapshot.fromMap(<Object?, Object?>{
        'newPoints': <double>[48.1, 11.1, 48.2, 11.2],
      });

      expect(copy.newPoints, const <LatLng>[
        LatLng(48.1, 11.1),
        LatLng(48.2, 11.2),
      ]);
    });

    test('a half coordinate at the end is dropped, not read', () {
      final copy = RecordingSnapshot.fromMap(<Object?, Object?>{
        'newPoints': <double>[48.1, 11.1, 48.2],
      });

      expect(copy.newPoints, const <LatLng>[LatLng(48.1, 11.1)]);
    });

    test('a snapshot without a position keeps it absent', () {
      final copy = RecordingSnapshot.fromMap(
        _snapshot(
          lastPosition: null,
          accuracyM: null,
          headingDeg: null,
        ).toMap(),
      );

      expect(copy.lastPosition, isNull);
      expect(copy.accuracyM, isNull);
      expect(copy.headingDeg, isNull);
    });

    test('an empty message reads as a blank, running ride', () {
      final copy = RecordingSnapshot.fromMap(const <Object?, Object?>{});

      expect(copy.rideId, '');
      expect(copy.status, RecordingStatus.active);
      expect(
        copy.startedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(copy.autoPaused, isFalse);
      expect(copy.distanceM, 0);
      expect(copy.elapsed, Duration.zero);
      expect(copy.moving, Duration.zero);
      expect(copy.pointCount, 0);
      expect(copy.newPoints, isEmpty);
      expect(copy.lastPosition, isNull);
    });

    test('the start always comes back as UTC', () {
      final copy = RecordingSnapshot.fromMap(_snapshot().toMap());

      expect(copy.startedAt.isUtc, isTrue);
    });

    test('whole numbers from the channel are read as doubles', () {
      // A platform channel hands an int back for a round double.
      final copy = RecordingSnapshot.fromMap(<Object?, Object?>{
        'distanceM': 1200,
        'speedMps': 5,
        'accuracyM': 4,
        'lat': 48,
        'lon': 11,
        'pointCount': 12.0,
      });

      expect(copy.distanceM, 1200.0);
      expect(copy.speedMps, 5.0);
      expect(copy.accuracyM, 4.0);
      expect(copy.lastPosition, const LatLng(48.0, 11.0));
      expect(copy.pointCount, 12);
    });
  });

  group('RecordingSnapshot.fromStats', () {
    const stats = RideStats(
      distanceM: 1234.5,
      movingTime: Duration(minutes: 11),
      elapsedTime: Duration(minutes: 12, seconds: 30),
      ascentM: 120.5,
      descentM: 80.25,
      maxSpeedMps: 9.75,
      pointCount: 750,
    );

    test('takes distance, times, climb and speeds from the statistics', () {
      final snapshot = RecordingSnapshot.fromStats(
        rideId: 'ride-1',
        status: RecordingStatus.active,
        startedAt: DateTime.utc(2026, 9, 12, 10),
        stats: stats,
        elapsed: const Duration(minutes: 13),
        speedMps: 5.5,
      );

      expect(snapshot.distanceM, 1234.5);
      expect(snapshot.moving, const Duration(minutes: 11));
      expect(snapshot.ascentM, 120.5);
      expect(snapshot.descentM, 80.25);
      expect(snapshot.maxSpeedMps, 9.75);
      expect(snapshot.pointCount, 750);
      expect(snapshot.avgSpeedMps, stats.avgSpeedMps);
      expect(snapshot.speedMps, 5.5);
    });

    test('the elapsed time is the clock, not the statistics', () {
      // A paused recording keeps counting wall-clock time while the journal
      // stands still, so the recorder passes its own elapsed time.
      final snapshot = RecordingSnapshot.fromStats(
        rideId: 'ride-1',
        status: RecordingStatus.paused,
        startedAt: DateTime.utc(2026, 9, 12, 10),
        stats: stats,
        elapsed: const Duration(minutes: 20),
      );

      expect(snapshot.elapsed, const Duration(minutes: 20));
      expect(snapshot.moving, const Duration(minutes: 11));
    });

    test('the puck follows the last fix and its accuracy', () {
      final snapshot = RecordingSnapshot.fromStats(
        rideId: 'ride-1',
        status: RecordingStatus.active,
        startedAt: DateTime.utc(2026, 9, 12, 10),
        stats: stats,
        elapsed: const Duration(minutes: 13),
        lastPoint: const TrackPoint(LatLng(48.1374, 11.5755), accuracyM: 4.5),
        newPoints: const <LatLng>[LatLng(48.1374, 11.5755)],
      );

      expect(snapshot.lastPosition, const LatLng(48.1374, 11.5755));
      expect(snapshot.accuracyM, 4.5);
      expect(snapshot.newPoints, const <LatLng>[LatLng(48.1374, 11.5755)]);
    });

    test('a ride without a fix yet has no position to show', () {
      final snapshot = RecordingSnapshot.fromStats(
        rideId: 'ride-1',
        status: RecordingStatus.active,
        startedAt: DateTime.utc(2026, 9, 12, 10),
        stats: RideStats.empty,
        elapsed: Duration.zero,
      );

      expect(snapshot.lastPosition, isNull);
      expect(snapshot.accuracyM, isNull);
      expect(snapshot.newPoints, isEmpty);
      expect(snapshot.autoPaused, isFalse);
    });

    test('an auto pause is carried through to the UI', () {
      final snapshot = RecordingSnapshot.fromStats(
        rideId: 'ride-1',
        status: RecordingStatus.paused,
        startedAt: DateTime.utc(2026, 9, 12, 10),
        stats: stats,
        elapsed: const Duration(minutes: 13),
        autoPaused: true,
      );

      expect(snapshot.autoPaused, isTrue);
      expect(snapshot.isManuallyPaused, isFalse);
    });
  });
}
