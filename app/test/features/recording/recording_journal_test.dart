import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki_geo/velorki_geo.dart';

TrackPoint _point(int index) => TrackPoint(
  LatLng(48 + index * 0.0001, 11.0001 * (index + 1)),
  ele: 500 + index.toDouble(),
  time: DateTime.utc(2026, 9, 12, 10, 0, index),
  speedMps: 5 + index.toDouble(),
  accuracyM: 4,
);

void main() {
  late Directory directory;
  late RecordingStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('velorki_journal');
    store = RecordingStore(directory);
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  group('RecordingJournal', () {
    test('flushes every five points or ten seconds', () {
      final journal = store.openJournal('ride');
      expect(journal.flushEveryPoints, 5);
      expect(journal.flushInterval, const Duration(seconds: 10));
    });

    test('appends 36-byte records behind a version header', () async {
      final journal = store.openJournal('ride');
      await journal.open();
      await journal.append(_point(0));
      await journal.append(_point(1));
      await journal.close();

      final bytes = await store.journalFile('ride').readAsBytes();
      expect(bytes.first, PackedTrack.version);
      expect(
        bytes.length,
        PackedTrack.headerLength + 2 * PackedTrack.bytesPerPoint,
      );
      expect(journal.pointCount, 2);
    });

    test('decodes back every field that was appended', () async {
      final journal = store.openJournal('ride');
      await journal.open();
      for (var i = 0; i < 12; i++) {
        await journal.append(_point(i));
      }
      await journal.close();

      final points = await store.readJournal('ride');
      expect(points, hasLength(12));
      expect(points.first.pos, _point(0).pos);
      expect(points.last.ele, 511);
      expect(points.last.time, DateTime.utc(2026, 9, 12, 10, 0, 11));
      expect(points[3].speedMps, 8);
      expect(points[3].accuracyM, 4);
    });

    test('the points are readable before the journal is closed', () async {
      final journal = store.openJournal('ride');
      await journal.open();
      await journal.append(_point(0));
      await journal.append(_point(1));
      await journal.append(_point(2));

      expect(await store.readJournal('ride'), hasLength(3));
      await journal.close();
    });

    test('ignores a truncated trailing record', () async {
      final file = store.journalFile('ride');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[
        ...PackedTrack.header(),
        ...PackedTrack.encodePoint(_point(0)),
        ...PackedTrack.encodePoint(_point(1)),
        // A record the crash cut in half.
        ...PackedTrack.encodePoint(_point(2)).sublist(0, 11),
      ]);

      expect(await readJournalPoints(file), hasLength(2));
    });

    test(
      'reopening truncates the half record so the file stays aligned',
      () async {
        final file = store.journalFile('ride');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(<int>[
          ...PackedTrack.header(),
          ...PackedTrack.encodePoint(_point(0)),
          ...PackedTrack.encodePoint(_point(1)).sublist(0, 20),
        ]);

        final journal = store.openJournal('ride');
        await journal.open();
        expect(journal.pointCount, 1);
        await journal.append(_point(2));
        await journal.close();

        final points = await store.readJournal('ride');
        expect(points, hasLength(2));
        expect(points.last.pos, _point(2).pos);
      },
    );

    test('an empty or missing file reads as no points', () async {
      expect(await store.readJournal('nothing'), isEmpty);
      final file = store.journalFile('empty');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(Uint8List(0));
      expect(await readJournalPoints(file), isEmpty);
    });

    test('delete removes the file', () async {
      final journal = store.openJournal('ride');
      await journal.open();
      await journal.append(_point(0));
      await journal.delete();
      expect(store.journalFile('ride').existsSync(), isFalse);
    });
  });

  group('RecordingStore state file', () {
    test('is absent until something is recorded', () async {
      expect(await store.readState(), isNull);
    });

    test(
      'round-trips the ride, the status, the route and the pauses',
      () async {
        final state = RecordingState(
          rideId: 'ride-1',
          startedAt: DateTime.utc(2026, 9, 12, 10),
          status: RecordingStatus.paused,
          routeId: 'route-7',
          pauses: <RidePause>[
            RidePause(
              startedAt: DateTime.utc(2026, 9, 12, 10, 5),
              endedAt: DateTime.utc(2026, 9, 12, 10, 8),
            ),
            RidePause(startedAt: DateTime.utc(2026, 9, 12, 10, 20)),
          ],
        );
        await store.writeState(state);

        expect(
          store.stateFile.path,
          p.join(directory.path, recordingStateFileName),
        );
        final read = await store.readState();
        expect(read, state);
        expect(read!.pauses.last.endedAt, isNull);
      },
    );

    test('a corrupt file reads as no recording', () async {
      await store.ensureDirectory();
      await store.stateFile.writeAsString('{not json');
      expect(await store.readState(), isNull);
    });

    test('a file without a ride id reads as no recording', () async {
      await store.ensureDirectory();
      await store.stateFile.writeAsString('{"status":"active"}');
      expect(await store.readState(), isNull);
    });

    test('clearState removes the file', () async {
      await store.writeState(
        RecordingState(
          rideId: 'ride-1',
          startedAt: DateTime.utc(2026, 9, 12, 10),
          status: RecordingStatus.active,
        ),
      );
      await store.clearState();
      expect(await store.readState(), isNull);
    });
  });
}
