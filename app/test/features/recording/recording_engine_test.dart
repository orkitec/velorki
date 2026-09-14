import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/data/recording_engine.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Drives an engine on a fake clock: no timers, no real GPS, no waiting on
/// wall-clock time.
///
/// The engine writes real files, and the work a tick sets off — flushing the
/// journal, writing the state file, then emitting the snapshot — finishes
/// whenever that I/O finishes, which on a loaded machine is far later than any
/// fixed delay would allow. So the harness waits for the snapshot the engine
/// emits at the end of that chain instead of for a stretch of real time.
class _Harness {
  _Harness(this.store, {this.autoPause = true});

  final RecordingStore store;
  final bool autoPause;
  final StreamController<TrackPoint> fixes = StreamController<TrackPoint>();
  final StreamController<DateTime> ticks = StreamController<DateTime>();
  final List<RecordingSnapshot> snapshots = <RecordingSnapshot>[];

  DateTime now = DateTime.utc(2026, 9, 12, 10);
  late final RecordingJournal journal;
  late final RecordingEngine engine;

  Completer<void>? _awaited;

  RecordingSnapshot get latest => snapshots.last;

  Future<void> start({
    RecordingStatus status = RecordingStatus.active,
    List<TrackPoint> seed = const <TrackPoint>[],
    List<RidePause> pauses = const <RidePause>[],
  }) async {
    journal = store.openJournal('ride-1');
    await journal.open();
    engine = RecordingEngine(
      store: store,
      journal: journal,
      initialState: RecordingState(
        rideId: 'ride-1',
        startedAt: now,
        status: status,
        pauses: pauses,
      ),
      fixes: fixes.stream,
      ticks: ticks.stream,
      clock: () => now,
      autoPause: autoPause,
    )..seed(seed);
    engine.snapshots.listen((snapshot) {
      snapshots.add(snapshot);
      final waiting = _awaited;
      _awaited = null;
      waiting?.complete();
    });
    await engine.start();
  }

  /// Emits a fix [seconds] after the start, [meters] of latitude north of 48°.
  ///
  /// Set [resumes] when the fix is the one that ends an auto-pause: that path
  /// writes the state file and emits a snapshot, so the wait is for the
  /// snapshot rather than for the plain hand-over to the engine.
  Future<void> fix(
    int seconds, {
    double meters = 0,
    double? ele,
    bool resumes = false,
  }) {
    now = DateTime.utc(2026, 9, 12, 10, 0, seconds);
    final point = TrackPoint(
      LatLng(48 + meters / 111194.9266, 11),
      ele: ele,
      time: now,
    );
    return resumes
        ? _emitting(() => fixes.add(point))
        : _handedOver(() => fixes.add(point));
  }

  /// Moves the clock to [seconds] and fires the one-second event.
  ///
  /// Every tick ends in exactly one snapshot — from the auto-pause path or
  /// from the plain one — which is emitted only once the journal flush and the
  /// state-file write of that tick are through.
  Future<void> tick(int seconds) {
    now = DateTime.utc(2026, 9, 12, 10, 0, seconds);
    return _emitting(() => ticks.add(now));
  }

  /// Runs [trigger] and waits for the snapshot it leads to.
  Future<void> _emitting(void Function() trigger) async {
    final completer = Completer<void>();
    _awaited = completer;
    trigger();
    // Only a deadlock guard, well inside the test timeout so the reason is
    // reported rather than a bare timeout; the wait itself is for the event.
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StateError('the engine emitted no snapshot'),
    );
  }

  /// Runs [trigger] and waits only for the engine to have taken the event:
  /// one turn of the event loop delivers it, and nothing on that path waits
  /// for a file.
  Future<void> _handedOver(void Function() trigger) async {
    trigger();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() async {
    await fixes.close();
    await ticks.close();
  }
}

void main() {
  late Directory directory;
  late RecordingStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('velorki_engine');
    store = RecordingStore(directory);
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('accumulates distance and journals every accepted fix', () async {
    final h = _Harness(store);
    await h.start();
    for (var i = 1; i <= 4; i++) {
      await h.fix(i, meters: 10.0 * i);
    }
    await h.tick(4);

    expect(h.latest.distanceM, closeTo(30, 0.1));
    expect(h.latest.pointCount, 4);
    expect(h.latest.moving, const Duration(seconds: 3));
    expect(h.latest.status, RecordingStatus.active);

    await h.engine.stop();
    expect(await store.readJournal('ride-1'), hasLength(4));
    await h.dispose();
  });

  test('the snapshot carries only the fixes since the previous one', () async {
    final h = _Harness(store);
    await h.start();
    await h.fix(1, meters: 10);
    await h.fix(2, meters: 20);
    await h.tick(2);
    expect(h.latest.newPoints, hasLength(2));

    await h.fix(3, meters: 30);
    await h.tick(3);
    expect(h.latest.newPoints, hasLength(1));

    await h.engine.stop();
    await h.dispose();
  });

  test('drops a GPS jump faster than 30 m/s', () async {
    final h = _Harness(store);
    await h.start();
    await h.fix(1, meters: 10);
    // 2 km in a second.
    await h.fix(2, meters: 2010);
    await h.fix(3, meters: 20);
    await h.tick(3);

    expect(h.latest.pointCount, 2);
    expect(h.latest.distanceM, closeTo(10, 0.1));

    await h.engine.stop();
    expect(await store.readJournal('ride-1'), hasLength(2));
    await h.dispose();
  });

  test('pauses itself after ten seconds without movement', () async {
    final h = _Harness(store);
    await h.start();
    await h.fix(1, meters: 10);
    await h.tick(5);
    expect(h.latest.status, RecordingStatus.active);

    await h.tick(11);
    expect(h.latest.status, RecordingStatus.paused);
    expect(h.latest.autoPaused, isTrue);
    expect(h.latest.speedMps, 0);
    expect((await store.readState())!.status, RecordingStatus.paused);

    // Moving again resumes on its own.
    await h.fix(12, meters: 30, resumes: true);
    expect(h.engine.status, RecordingStatus.active);
    expect(h.engine.isAutoPaused, isFalse);
    expect((await store.readState())!.status, RecordingStatus.active);

    await h.engine.stop();
    await h.dispose();
  });

  test('auto-pause can be switched off', () async {
    final h = _Harness(store, autoPause: false);
    await h.start();
    await h.fix(1, meters: 10);
    await h.tick(60);
    expect(h.latest.status, RecordingStatus.active);

    await h.engine.stop();
    await h.dispose();
  });

  test('a manual pause drops fixes and records the interval', () async {
    final h = _Harness(store);
    await h.start();
    await h.fix(1, meters: 10);

    h.now = DateTime.utc(2026, 9, 12, 10, 0, 2);
    await h.engine.pause();
    expect(h.engine.status, RecordingStatus.paused);
    expect(h.engine.isAutoPaused, isFalse);

    await h.fix(3, meters: 100);
    expect(h.engine.stats.pointCount, 1, reason: 'the fix was dropped');

    h.now = DateTime.utc(2026, 9, 12, 10, 0, 4);
    await h.engine.resume();
    await h.fix(5, meters: 120);
    expect(h.engine.stats.pointCount, 2);

    final state = await store.readState();
    expect(state!.status, RecordingStatus.active);
    expect(state.pauses, hasLength(1));
    expect(state.pauses.single.startedAt, DateTime.utc(2026, 9, 12, 10, 0, 2));
    expect(state.pauses.single.endedAt, DateTime.utc(2026, 9, 12, 10, 0, 4));

    await h.engine.stop();
    expect(await store.readJournal('ride-1'), hasLength(2));
    await h.dispose();
  });

  test('ascent uses the three-metre hysteresis live as well', () async {
    final h = _Harness(store);
    await h.start();
    await h.fix(0, ele: 100);
    await h.fix(1, meters: 10, ele: 101);
    await h.fix(2, meters: 20, ele: 104);
    await h.fix(3, meters: 30, ele: 100);
    await h.tick(3);

    expect(h.latest.ascentM, closeTo(4, 0.001));
    expect(h.latest.descentM, closeTo(4, 0.001));

    await h.engine.stop();
    await h.dispose();
  });

  test('seeding continues the statistics of a resumed recording', () async {
    final h = _Harness(store);
    await h.start(
      seed: <TrackPoint>[
        TrackPoint(
          const LatLng(48, 11),
          time: DateTime.utc(2026, 9, 12, 9, 59),
        ),
        TrackPoint(
          const LatLng(48.001, 11),
          time: DateTime.utc(2026, 9, 12, 9, 59, 30),
        ),
      ],
    );
    await h.tick(1);
    expect(h.latest.pointCount, 2);
    expect(h.latest.distanceM, closeTo(111.19, 0.1));

    await h.engine.stop();
    await h.dispose();
  });

  test('a seam is a break however short the gap across it is', () async {
    // What "Continue this ride" hands the engine: the ride's own fixes, and a
    // seam from the moment it was stopped to the moment it was picked up —
    // two seconds, far inside the 30 s gap rule.
    final h = _Harness(store);
    await h.start(
      seed: <TrackPoint>[
        TrackPoint(
          const LatLng(48, 11),
          ele: 500,
          time: DateTime.utc(2026, 9, 12, 9, 59, 58),
        ),
        TrackPoint(
          const LatLng(48.0001, 11),
          ele: 501,
          time: DateTime.utc(2026, 9, 12, 9, 59, 59),
        ),
      ],
      pauses: <RidePause>[
        RidePause(
          startedAt: DateTime.utc(2026, 9, 12, 9, 59, 59),
          endedAt: DateTime.utc(2026, 9, 12, 10),
          seam: true,
        ),
      ],
    );
    await h.tick(0);
    expect(h.latest.distanceM, closeTo(11.12, 0.01));
    expect(h.latest.moving, const Duration(seconds: 1));

    // The first fix after the hand-over: no distance, no moving time, even
    // though it is only two seconds after the last one.
    await h.fix(1, meters: 31.12);
    await h.tick(1);
    expect(h.latest.pointCount, 3);
    expect(h.latest.distanceM, closeTo(11.12, 0.01));
    expect(h.latest.moving, const Duration(seconds: 1));

    // From there the ride goes on as any other.
    await h.fix(3, meters: 51.12);
    await h.tick(3);
    expect(h.latest.distanceM, closeTo(31.12, 0.05));
    expect(h.latest.moving, const Duration(seconds: 3));

    await h.engine.stop();
    await h.dispose();
  });

  test('stop closes the journal and reports an idle snapshot', () async {
    final h = _Harness(store);
    await h.start();
    await h.fix(1, meters: 10);

    final stats = await h.engine.stop();
    expect(stats.pointCount, 1);
    expect(h.latest.status, RecordingStatus.idle);
    expect(h.journal.isOpen, isFalse);
    // The state file survives: only writing the rides row may remove it.
    expect(await store.readState(), isNotNull);
    await h.dispose();
  });
}
