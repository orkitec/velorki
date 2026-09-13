import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/data/recording_task_handler.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

/// When the recording under test started; every time in this suite is an
/// offset from it.
final DateTime _start = DateTime.utc(2026, 9, 12, 10);

/// Drives the task handler the way the Android service does, on a fake clock
/// and a temporary directory: no platform channel, no GPS, no waiting on
/// wall-clock time.
///
/// The handler's work ends in I/O — flushing the journal, writing the state
/// file — so the harness waits for the message the handler sends to the UI
/// isolate at the end of that chain rather than for a stretch of real time.
class _Harness {
  _Harness(this.store);

  final RecordingStore store;
  final FakeForegroundServiceHost host = FakeForegroundServiceHost();
  final StreamController<TrackPoint> fixes =
      StreamController<TrackPoint>.broadcast();

  DateTime now = _start;

  late final RecordingTaskHandler handler = RecordingTaskHandler(
    host: host,
    openStore: () async => store,
    fixes: () => fixes.stream,
    clock: () => now,
  );

  /// The snapshots that reached the UI isolate.
  List<RecordingSnapshot> get snapshots => host.snapshots;

  /// The last snapshot that reached the UI isolate.
  RecordingSnapshot get latest => snapshots.last;

  /// Starts the service at [seconds] after [_start].
  ///
  /// Waits for the first snapshot when one is expected: the engine emits it
  /// while starting, and the broadcast stream delivers it a turn later.
  Future<void> start({int seconds = 4, bool records = true}) async {
    now = _at(seconds);
    if (!records) {
      await handler.onStart(now, TaskStarter.developer);
      return;
    }
    await _awaitingMessage(() => handler.onStart(now, TaskStarter.developer));
  }

  /// Fires the service's repeat event at [seconds] after [_start].
  Future<void> tick(int seconds) => _awaitingMessage(() {
    now = _at(seconds);
    handler.onRepeatEvent(now);
  });

  /// Delivers a fix [meters] north of 48°, [seconds] after [_start].
  ///
  /// Waits only for the handler to have taken the fix: journalling it emits
  /// nothing, the next tick reports it.
  Future<void> fix(int seconds, {required double meters}) async {
    now = _at(seconds);
    fixes.add(_point(seconds: seconds, meters: meters));
    await _settle();
  }

  /// Sends a command the way the UI isolate does, waiting for the message it
  /// leads to.
  Future<void> command(String name) => _awaitingMessage(
    () => handler.onReceiveData(<String, Object?>{recordingCommandKey: name}),
  );

  /// Hands [data] to the handler and lets the event loop run, for the cases
  /// where nothing at all is supposed to happen.
  Future<void> deliver(Object data) async {
    handler.onReceiveData(data);
    await _settle();
  }

  Future<void> _awaitingMessage(FutureOr<void> Function() trigger) async {
    final next = host.nextMessage();
    await trigger();
    // Only a deadlock guard, well inside the test timeout so the reason is
    // reported rather than a bare timeout; the wait itself is for the message.
    await next.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StateError('the recorder sent no message'),
    );
  }

  Future<void> _settle() => Future<void>.delayed(Duration.zero);

  Future<void> dispose() async {
    await handler.onDestroy(now, false);
    await fixes.close();
  }
}

DateTime _at(int seconds) => _start.add(Duration(seconds: seconds));

TrackPoint _point({required int seconds, required double meters}) =>
    TrackPoint(LatLng(48 + meters / 111194.9266, 11), time: _at(seconds));

void main() {
  late Directory directory;
  late RecordingStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('velorki_task_handler');
    store = RecordingStore(directory);
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  /// Writes the state file of a ride that is under way.
  Future<void> writeState({RecordingStatus status = RecordingStatus.active}) =>
      store.writeState(
        RecordingState(rideId: 'ride-1', startedAt: _start, status: status),
      );

  /// Journals [points] fixes ten metres and one second apart, as an
  /// interrupted recording would have left them behind.
  Future<void> writeJournal(int points) async {
    final journal = store.openJournal('ride-1');
    await journal.open();
    for (var i = 0; i < points; i++) {
      await journal.append(_point(seconds: i, meters: 10.0 * i));
    }
    await journal.close();
  }

  test('stops the service when there is no ride to record', () async {
    final h = _Harness(store);
    await h.start(records: false);

    expect(h.host.stopServiceCalls, 1);
    expect(h.host.messages, isEmpty);
    expect(
      h.fixes.hasListener,
      isFalse,
      reason: 'no engine means nobody listens to the GPS',
    );

    // A command that arrives anyway finds no recorder and sends nothing back.
    await h.deliver(<String, Object?>{
      recordingCommandKey: recordingCommandSync,
    });
    expect(h.host.messages, isEmpty);

    await h.dispose();
  });

  test('picks up an unfinished ride where its journal left off', () async {
    await writeState();
    await writeJournal(4);

    final h = _Harness(store);
    await h.start();

    expect(h.latest.rideId, 'ride-1');
    expect(h.latest.pointCount, 4);
    expect(
      h.latest.distanceM,
      closeTo(30, 0.1),
      reason: 'the journalled metres are folded back in, not thrown away',
    );

    // The next fix continues from the last journalled one.
    await h.fix(5, meters: 40);
    await h.tick(6);
    expect(h.latest.pointCount, 5);
    expect(h.latest.distanceM, closeTo(40, 0.1));

    await h.dispose();
  });

  test('sends a snapshot to the UI for every repeat event', () async {
    await writeState();
    await writeJournal(2);

    final h = _Harness(store);
    await h.start();
    final afterStart = h.snapshots.length;

    await h.tick(5);
    await h.tick(6);
    await h.tick(7);

    expect(h.snapshots, hasLength(afterStart + 3));
    expect(h.latest.status, RecordingStatus.active);

    await h.dispose();
  });

  test('pauses and resumes the recording on command', () async {
    await writeState();
    await writeJournal(2);

    final h = _Harness(store);
    await h.start();

    await h.command(recordingCommandPause);
    expect(h.latest.status, RecordingStatus.paused);
    expect((await store.readState())!.status, RecordingStatus.paused);

    // A fix during the break is dropped, which is what makes the pause a gap.
    await h.fix(6, meters: 100);
    await h.tick(7);
    expect(h.latest.pointCount, 2);

    await h.command(recordingCommandResume);
    expect(h.latest.status, RecordingStatus.active);
    expect((await store.readState())!.status, RecordingStatus.active);

    await h.dispose();
  });

  test('answers a sync command without waiting for the next tick', () async {
    await writeState();
    await writeJournal(3);

    final h = _Harness(store);
    await h.start();
    final afterStart = h.snapshots.length;

    await h.command(recordingCommandSync);

    expect(h.snapshots, hasLength(afterStart + 1));
    expect(h.latest.pointCount, 3);
    expect(h.latest.rideId, 'ride-1');

    await h.dispose();
  });

  test('ignores a payload that is not a map', () async {
    await writeState();

    final h = _Harness(store);
    await h.start();
    final afterStart = h.snapshots.length;

    await h.deliver('stop');
    await h.deliver(42);

    expect(h.snapshots, hasLength(afterStart));
    expect((await store.readState())!.status, RecordingStatus.active);

    await h.dispose();
  });

  test('ignores a command it does not know', () async {
    await writeState();

    final h = _Harness(store);
    await h.start();
    final afterStart = h.snapshots.length;

    await h.deliver(<String, Object?>{recordingCommandKey: 'fly'});
    await h.deliver(<String, Object?>{'something': 'else'});

    expect(h.snapshots, hasLength(afterStart));
    expect((await store.readState())!.status, RecordingStatus.active);

    await h.dispose();
  });

  test('acknowledges a stop once the journal is closed', () async {
    await writeState();
    await writeJournal(4);

    final h = _Harness(store);
    await h.start();
    // A fix the journal only flushes when it is closed properly.
    await h.fix(5, meters: 40);

    await h.command(recordingCommandStop);

    expect(h.host.messageKinds.last, recordingStoppedMessage);
    expect(
      await store.readJournal('ride-1'),
      hasLength(5),
      reason: 'the acknowledgement waits for the closed journal',
    );
    expect(
      h.fixes.hasListener,
      isFalse,
      reason: 'the recorder let go of the GPS',
    );

    // The recorder is gone: a later command finds nothing to report.
    final afterStop = h.host.messages.length;
    await h.deliver(<String, Object?>{
      recordingCommandKey: recordingCommandSync,
    });
    expect(h.host.messages, hasLength(afterStop));

    await h.dispose();
  });

  test('updates the notification at most every five seconds', () async {
    await writeState();
    await writeJournal(2);

    final h = _Harness(store);
    // The first snapshot always writes the notification: there is none yet.
    await h.start();
    expect(h.host.notificationTexts, hasLength(1));

    // Two seconds later — inside the interval, the notification stands.
    await h.tick(6);
    expect(h.host.notificationTexts, hasLength(1));

    // Six seconds after the last update the rider gets fresh numbers.
    await h.tick(10);
    expect(h.host.notificationTexts, hasLength(2));
    expect(h.host.notificationTexts.last, '0.0 km · 00:10');

    await h.dispose();
  });

  test('stops the recording when the service is destroyed', () async {
    await writeState();
    await writeJournal(4);

    final h = _Harness(store);
    await h.start();
    await h.fix(5, meters: 40);

    await h.handler.onDestroy(h.now, false);

    expect(
      await store.readJournal('ride-1'),
      hasLength(5),
      reason: 'the journal was closed, not just dropped',
    );
    expect(
      h.fixes.hasListener,
      isFalse,
      reason: 'the recorder let go of the GPS',
    );
    expect(
      () => h.handler.onRepeatEvent(h.now),
      throwsStateError,
      reason: 'the tick stream is released with the recorder',
    );

    // The service may report the destruction twice; that must stay harmless.
    await h.handler.onDestroy(h.now, true);

    await h.fixes.close();
  });

  test('brings the app to the front when the notification is tapped', () async {
    await writeState();

    final h = _Harness(store);
    await h.start();

    h.handler.onNotificationPressed();

    expect(h.host.launchAppCalls, 1);

    await h.dispose();
  });

  group('the notification text', () {
    RecordingSnapshot snapshot({
      double distanceM = 0,
      Duration elapsed = Duration.zero,
      RecordingStatus status = RecordingStatus.active,
    }) => RecordingSnapshot(
      rideId: 'ride-1',
      status: status,
      startedAt: _start,
      distanceM: distanceM,
      elapsed: elapsed,
    );

    test('reports the distance in kilometres with one decimal', () {
      expect(
        notificationTextFor(snapshot(distanceM: 12345)),
        '12.3 km · 00:00',
      );
      expect(notificationTextFor(snapshot(distanceM: 960)), '1.0 km · 00:00');
      expect(notificationTextFor(snapshot()), '0.0 km · 00:00');
    });

    test('counts in minutes and seconds below an hour', () {
      expect(
        notificationTextFor(snapshot(elapsed: const Duration(seconds: 65))),
        '0.0 km · 01:05',
      );
      expect(
        notificationTextFor(snapshot(elapsed: const Duration(minutes: 59))),
        '0.0 km · 59:00',
      );
    });

    test('adds the hours once the ride is longer than one', () {
      expect(
        notificationTextFor(snapshot(elapsed: const Duration(seconds: 3723))),
        '0.0 km · 1:02:03',
      );
      expect(
        notificationTextFor(snapshot(elapsed: const Duration(hours: 2))),
        '0.0 km · 2:00:00',
      );
    });

    test('marks a paused ride with a pause sign', () {
      expect(
        notificationTextFor(
          snapshot(
            distanceM: 4200,
            elapsed: const Duration(minutes: 20, seconds: 7),
            status: RecordingStatus.paused,
          ),
        ),
        '4.2 km · 20:07 · ⏸',
      );
    });
  });
}
