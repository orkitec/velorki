import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  late Directory directory;
  late RecordingStore store;

  RecoveryService recovery({required bool serviceRunning}) => RecoveryService(
    store: store,
    isServiceRunning: () async => serviceRunning,
  );

  Future<void> writeState(RecordingStatus status) => store.writeState(
    RecordingState(
      rideId: 'ride-1',
      startedAt: DateTime.utc(2026, 9, 12, 10),
      status: status,
      routeId: 'route-3',
    ),
  );

  Future<void> writeJournal(int points) async {
    final journal = store.openJournal('ride-1');
    await journal.open();
    for (var i = 0; i < points; i++) {
      await journal.append(
        TrackPoint(
          LatLng(48 + i * 0.0001, 11),
          time: DateTime.utc(2026, 9, 12, 10, 0, i),
        ),
      );
    }
    await journal.close();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('velorki_recovery');
    store = RecordingStore(directory);
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('no state file means nothing to recover', () async {
    expect(
      await recovery(serviceRunning: false).checkOnLaunch(),
      isA<NoRecovery>(),
    );
  });

  test('active with a running service reattaches', () async {
    await writeState(RecordingStatus.active);
    await writeJournal(3);

    final result = await recovery(serviceRunning: true).checkOnLaunch();
    expect(result, isA<ReattachRecording>());
    expect((result as ReattachRecording).state.rideId, 'ride-1');
    expect(result.state.routeId, 'route-3');
  });

  test('active without a running service asks resume or finish', () async {
    await writeState(RecordingStatus.active);
    await writeJournal(4);

    final result = await recovery(serviceRunning: false).checkOnLaunch();
    expect(result, isA<InterruptedRecording>());
    final interrupted = result as InterruptedRecording;
    expect(interrupted.state.status, RecordingStatus.active);
    expect(interrupted.stats.pointCount, 4);
    expect(interrupted.stats.distanceM, greaterThan(30));
    expect(interrupted.stats.movingTime, const Duration(seconds: 3));
  });

  test('paused without a running service asks resume or finish', () async {
    await writeState(RecordingStatus.paused);
    await writeJournal(2);

    final result = await recovery(serviceRunning: false).checkOnLaunch();
    expect(result, isA<InterruptedRecording>());
    expect(
      (result as InterruptedRecording).state.status,
      RecordingStatus.paused,
    );
  });

  test('paused with a running service reattaches', () async {
    await writeState(RecordingStatus.paused);

    expect(
      await recovery(serviceRunning: true).checkOnLaunch(),
      isA<ReattachRecording>(),
    );
  });

  test(
    'an interrupted recording without a journal still offers a choice',
    () async {
      await writeState(RecordingStatus.active);

      final result = await recovery(serviceRunning: false).checkOnLaunch();
      expect(result, isA<InterruptedRecording>());
      expect((result as InterruptedRecording).stats.pointCount, 0);
    },
  );
}
