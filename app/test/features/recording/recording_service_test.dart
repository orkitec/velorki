import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/sensors/domain/sensor_snapshot.dart';

final DateTime _start = DateTime.utc(2026, 9, 12, 10);

SensorSnapshot _reading(int heartRate, int second) => SensorSnapshot(
  heartRateBpm: heartRate,
  heartRateAt: _start.add(Duration(seconds: second)),
);

void main() {
  late VelorkiDatabase db;
  late List<Map<String, Object?>> sent;

  setUp(() {
    db = VelorkiDatabase.memory();
    sent = <Map<String, Object?>>[];
  });

  tearDown(() => db.close());

  /// The Android service with the port to the task isolate replaced by a list,
  /// on a clock the test winds forward.
  ///
  /// Nothing here opens the store: forwarding the sensors touches neither the
  /// journal nor the database.
  ForegroundTaskRecordingService service(DateTime Function() now) =>
      ForegroundTaskRecordingService(
        store: Future<RecordingStore>.value(
          RecordingStore(Directory(Directory.systemTemp.path)),
        ),
        rides: RideRepository(db.ridesDao),
        clock: now,
        sendToTask: sent.add,
      );

  group('forwarding the sensors to the service isolate', () {
    test('the first snapshot goes out at once', () {
      final now = _start;
      final recorder = service(() => now)..publishSensors(_reading(142, 0));

      expect(sent, hasLength(1));
      expect(sent.single[recordingMessageKind], recordingSensorsMessage);
      expect(SensorSnapshot.fromMap(sent.single).heartRateBpm, 142);
      unawaited(recorder.dispose());
    });

    test('an unchanged snapshot is not sent again', () {
      final now = _start;
      final recorder = service(() => now)
        ..publishSensors(_reading(142, 0))
        ..publishSensors(_reading(142, 0));

      expect(sent, hasLength(1));
      unawaited(recorder.dispose());
    });

    test('at most one message per second, and always the newest', () {
      fakeAsync((async) {
        var now = _start;
        final recorder = service(() => now)..publishSensors(_reading(140, 0));
        expect(sent, hasLength(1));

        // Three more inside the same second: all held, the last one wins.
        for (final beat in [141, 142, 143]) {
          now = now.add(const Duration(milliseconds: 200));
          recorder.publishSensors(_reading(beat, 1));
        }
        expect(sent, hasLength(1), reason: 'still inside the interval');

        now = _start.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));

        expect(sent, hasLength(2));
        expect(SensorSnapshot.fromMap(sent.last).heartRateBpm, 143);
        unawaited(recorder.dispose());
      });
    });

    test('a snapshot after the interval goes straight out', () {
      fakeAsync((async) {
        var now = _start;
        final recorder = service(() => now)..publishSensors(_reading(140, 0));

        now = _start.add(const Duration(seconds: 5));
        recorder.publishSensors(_reading(150, 5));

        expect(sent, hasLength(2));
        expect(SensorSnapshot.fromMap(sent.last).heartRateBpm, 150);
        async.flushTimers();
        unawaited(recorder.dispose());
      });
    });

    test('disposing drops the pending message rather than firing later', () {
      fakeAsync((async) {
        var now = _start;
        final recorder = service(() => now)..publishSensors(_reading(140, 0));
        now = now.add(const Duration(milliseconds: 100));
        recorder.publishSensors(_reading(150, 1));

        unawaited(recorder.dispose());
        async.elapse(const Duration(seconds: 5));

        expect(sent, hasLength(1));
      });
    });
  });
}
