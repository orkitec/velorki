import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../map/data/position_provider.dart';
import '../domain/gps_precision.dart';
import '../domain/recording_snapshot.dart';
import '../domain/recording_state.dart';
import '../domain/ride.dart';
import 'recording_engine.dart';
import 'recording_journal.dart';
import 'recording_positions.dart';
import 'recording_task_handler.dart';
import 'ride_repository.dart';

/// Starting a recording failed; the message is meant for a snack bar.
class RecordingException implements Exception {
  /// Creates the exception.
  const RecordingException(this.message);

  /// What went wrong, already readable.
  final String message;

  @override
  String toString() => 'RecordingException: $message';
}

/// Everything the recording UI may ask of the recorder.
///
/// One interface, two very different implementations: on Android the recorder
/// lives in a foreground service isolate and this is a remote control; on iOS
/// it runs in this very isolate. The screens cannot tell the difference, and
/// the widget tests use a third implementation that records calls.
abstract class RecordingService {
  /// One snapshot per second while a ride is being recorded.
  Stream<RecordingSnapshot> get snapshots;

  /// The last snapshot seen, so a screen that is rebuilt shows numbers at once.
  RecordingSnapshot? get lastSnapshot;

  /// Whether a recording is under way — on Android also when the app was
  /// restarted while the service kept running.
  Future<bool> get isRunning;

  /// The unfinished recording described by `recording_state.json`, if any.
  Future<RecordingState?> pendingState();

  /// Starts a ride, optionally following the saved route [routeId].
  ///
  /// [notificationTitle] is the first line of the Android notification; it is
  /// passed in because only the UI knows the locale. [precision] is the GPS
  /// profile the ride is recorded at; it travels with the recording state,
  /// which is how it reaches the service isolate.
  Future<void> start({
    required String notificationTitle,
    String? routeId,
    GpsPrecision precision = GpsPrecision.normal,
  });

  /// Suspends journalling.
  Future<void> pause();

  /// Continues journalling.
  Future<void> resume();

  /// Finishes the ride and writes it to the database.
  ///
  /// Returns the saved ride, or `null` when too little was recorded to keep —
  /// the journal and the state file are removed either way.
  Future<Ride?> stop({required String rideName});

  /// Re-subscribes to a recorder that outlived the UI. Returns whether one was
  /// still running.
  Future<bool> reattach();

  /// Continues the interrupted recording [state] instead of finishing it.
  Future<void> resumeInterrupted(
    RecordingState state, {
    required String notificationTitle,
    GpsPrecision? precision,
  });

  /// Records onto the already finished ride [ride], continuing its track and
  /// its figures instead of starting a new one.
  ///
  /// Does nothing when a recording is already under way.
  Future<void> continueRide(
    Ride ride, {
    required String notificationTitle,
    GpsPrecision precision = GpsPrecision.normal,
  });

  /// Turns the journal of the interrupted recording [state] into a ride.
  Future<Ride?> finishInterrupted(
    RecordingState state, {
    required String rideName,
  });

  /// Throws the interrupted recording [state] away.
  Future<void> discardInterrupted(RecordingState state);

  /// Releases the snapshot stream; a running Android service keeps going.
  Future<void> dispose();
}

/// What both implementations share: the store, the finalising and the
/// bookkeeping of the last snapshot.
abstract base class BaseRecordingService implements RecordingService {
  /// Creates the base.
  BaseRecordingService({
    required Future<RecordingStore> store,
    required this.rides,
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _storeFuture = store,
       _uuid = uuid ?? const Uuid(),
       clock = clock ?? DateTime.now;

  /// The rides table.
  final RideRepository rides;

  /// The clock, injected so tests can pin the dates.
  final DateTime Function() clock;

  final Future<RecordingStore> _storeFuture;
  final Uuid _uuid;
  final StreamController<RecordingSnapshot> snapshotSink =
      StreamController<RecordingSnapshot>.broadcast();

  RecordingSnapshot? _lastSnapshot;

  @override
  Stream<RecordingSnapshot> get snapshots => snapshotSink.stream;

  @override
  RecordingSnapshot? get lastSnapshot => _lastSnapshot;

  /// The journal directory, opened once.
  Future<RecordingStore> get store => _storeFuture;

  @override
  Future<RecordingState?> pendingState() async => (await store).readState();

  @override
  Future<Ride?> finishInterrupted(
    RecordingState state, {
    required String rideName,
  }) => finalize(state, rideName: rideName);

  /// Hands [ride] back to the recorder.
  ///
  /// The ride's own track becomes the journal of a recording with the ride's
  /// id, and the state file gets the ride's start, its route and its pauses
  /// plus the seam it is being picked up across. From there this is an
  /// interrupted recording like any other, so the resume machinery — and on
  /// Android the foreground service that reads the very same two files — does
  /// the rest. Finishing it writes the row again, id and all.
  ///
  /// The upload markers go: a continued ride is not the ride that was sent.
  @override
  Future<void> continueRide(
    Ride ride, {
    required String notificationTitle,
    GpsPrecision precision = GpsPrecision.normal,
  }) async {
    if (await isRunning) return;
    final opened = await store;
    await opened.writeJournal(ride.id, ride.points);
    final state = continuationState(ride, precision: precision);
    await opened.writeState(state);
    await rides.clearUploads(ride.id);
    await resumeInterrupted(
      state,
      notificationTitle: notificationTitle,
      precision: precision,
    );
  }

  /// The recording that continues [ride]; see [continueRide].
  RecordingState continuationState(
    Ride ride, {
    GpsPrecision precision = GpsPrecision.normal,
  }) => RecordingState(
    rideId: ride.id,
    startedAt: ride.startedAt,
    status: RecordingStatus.active,
    routeId: ride.routeId,
    precision: precision,
    pauses: <RidePause>[
      ...ride.pauses,
      RidePause(startedAt: ride.endedAt, endedAt: clock().toUtc(), seam: true),
    ],
  );

  @override
  Future<void> discardInterrupted(RecordingState state) async {
    final opened = await store;
    await opened.deleteJournal(state.rideId);
    await opened.clearState();
  }

  @override
  Future<void> dispose() async {
    if (!snapshotSink.isClosed) await snapshotSink.close();
  }

  /// Publishes [snapshot] to the UI.
  void publish(RecordingSnapshot snapshot) {
    _lastSnapshot = snapshot.status == RecordingStatus.idle ? null : snapshot;
    if (!snapshotSink.isClosed) snapshotSink.add(snapshot);
  }

  /// A fresh recording state for a ride that starts now.
  RecordingState newState({
    String? routeId,
    GpsPrecision precision = GpsPrecision.normal,
  }) => RecordingState(
    rideId: _uuid.v4(),
    startedAt: clock().toUtc(),
    status: RecordingStatus.active,
    routeId: routeId,
    precision: precision,
  );

  /// Reads the journal of [state], writes the `rides` row and cleans up.
  ///
  /// A recording with fewer than two fixes is thrown away instead of becoming
  /// a ride of zero metres.
  Future<Ride?> finalize(
    RecordingState state, {
    required String rideName,
  }) async {
    final opened = await store;
    final points = await opened.readJournal(state.rideId);
    if (points.length < 2) {
      await opened.deleteJournal(state.rideId);
      await opened.clearState();
      _lastSnapshot = null;
      return null;
    }
    // A continued ride replaces its own row and keeps what the rider gave it:
    // the name they may have typed and the notes they may have written. Only
    // the uploads are dropped, and those went at the moment it was continued.
    final continued = state.isContinuation
        ? await rides.rideById(state.rideId)
        : null;
    final ride = await rides.finalizeRide(
      rideId: state.rideId,
      name: continued?.name ?? rideName,
      points: points,
      startedAt: state.startedAt,
      endedAt: points.last.time ?? clock().toUtc(),
      routeId: state.routeId,
      pauses: state.pauses,
      notes: continued?.notes,
    );
    await opened.deleteJournal(state.rideId);
    await opened.clearState();
    _lastSnapshot = null;
    return ride;
  }
}

/// The recorder for platforms without a service isolate: iOS, and the desktop
/// builds used while developing.
///
/// The engine runs right here, fed by geolocator. On iOS `UIBackgroundModes
/// location` keeps this isolate alive with the screen off; force-quitting the
/// app ends the recording, which is what the recovery dialog is for.
final class MainIsolateRecordingService extends BaseRecordingService {
  /// Creates the service.
  MainIsolateRecordingService({
    required super.store,
    required super.rides,
    required this.positions,
    super.uuid,
    super.clock,
    this.platform,
  });

  /// Where the fixes come from.
  final PositionSource positions;

  /// Overrides the platform the location settings are built for; tests only.
  final TargetPlatform? platform;

  RecordingEngine? _engine;
  StreamSubscription<RecordingSnapshot>? _subscription;

  @override
  Future<bool> get isRunning async => _engine != null;

  @override
  Future<void> start({
    required String notificationTitle,
    String? routeId,
    GpsPrecision precision = GpsPrecision.normal,
  }) async {
    if (_engine != null) return;
    await _run(
      newState(routeId: routeId, precision: precision),
      seed: const <TrackPoint>[],
    );
  }

  @override
  Future<void> resumeInterrupted(
    RecordingState state, {
    required String notificationTitle,
    GpsPrecision? precision,
  }) async {
    if (_engine != null) return;
    final opened = await store;
    await _run(
      state.copyWith(status: RecordingStatus.active, precision: precision),
      seed: await opened.readJournal(state.rideId),
    );
  }

  @override
  Future<void> pause() async => _engine?.pause();

  @override
  Future<void> resume() async => _engine?.resume();

  @override
  Future<Ride?> stop({required String rideName}) async {
    final engine = _engine;
    _engine = null;
    await _subscription?.cancel();
    _subscription = null;
    if (engine == null) {
      final pending = await pendingState();
      return pending == null ? null : finalize(pending, rideName: rideName);
    }
    await engine.stop();
    publish(engine.snapshot);
    return finalize(engine.state, rideName: rideName);
  }

  @override
  Future<bool> reattach() async => _engine != null;

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _engine?.stop();
    _engine = null;
    await super.dispose();
  }

  Future<void> _run(
    RecordingState state, {
    required List<TrackPoint> seed,
  }) async {
    final opened = await store;
    await opened.writeState(state);
    final journal = opened.openJournal(state.rideId);
    await journal.open();
    final engine = RecordingEngine(
      store: opened,
      journal: journal,
      initialState: state,
      fixes: recordingFixes(
        positions,
        platform: platform,
        precision: state.precision,
      ),
      ticks: Stream<DateTime>.periodic(
        const Duration(seconds: 1),
        (_) => clock(),
      ),
      clock: clock,
    )..seed(seed);
    _subscription = engine.snapshots.listen(publish);
    await engine.start();
    _engine = engine;
  }
}

/// Id of the recording notification, so it is replaced rather than stacked.
const int recordingServiceId = 4711;

/// The recorder on Android: a foreground service with the `location` type.
///
/// This class never touches the GPS itself. It writes `recording_state.json`,
/// starts the service — which reads that file and does the work — and then
/// only relays snapshots and commands.
final class ForegroundTaskRecordingService extends BaseRecordingService {
  /// Creates the service.
  ForegroundTaskRecordingService({
    required super.store,
    required super.rides,
    super.uuid,
    super.clock,
  });

  bool _listening = false;
  Completer<void>? _stopped;

  @override
  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start({
    required String notificationTitle,
    String? routeId,
    GpsPrecision precision = GpsPrecision.normal,
  }) async {
    if (await isRunning) return;
    final opened = await store;
    final state = newState(routeId: routeId, precision: precision);
    await opened.deleteJournal(state.rideId);
    await opened.writeState(state);
    await _startService(notificationTitle);
  }

  @override
  Future<void> resumeInterrupted(
    RecordingState state, {
    required String notificationTitle,
    GpsPrecision? precision,
  }) async {
    if (await isRunning) return;
    final opened = await store;
    await opened.writeState(
      state.copyWith(status: RecordingStatus.active, precision: precision),
    );
    await _startService(notificationTitle);
  }

  @override
  Future<void> pause() async => _command(recordingCommandPause);

  @override
  Future<void> resume() async => _command(recordingCommandResume);

  @override
  Future<Ride?> stop({required String rideName}) async {
    final state = await pendingState();
    if (await isRunning) {
      final stopped = _stopped = Completer<void>();
      _command(recordingCommandStop);
      // The acknowledgement means the journal is closed. If it never comes,
      // stopping the service runs onDestroy, which closes it too.
      await stopped.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      _stopped = null;
      await FlutterForegroundTask.stopService();
    }
    _detach();
    if (state == null) return null;
    return finalize(state, rideName: rideName);
  }

  @override
  Future<bool> reattach() async {
    if (!await isRunning) return false;
    _attach();
    _command(recordingCommandSync);
    return true;
  }

  @override
  Future<void> dispose() async {
    _detach();
    await super.dispose();
  }

  Future<void> _startService(String notificationTitle) async {
    _attach();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'velorki_recording',
        channelName: notificationTitle,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // One event per second drives the snapshot and the auto-pause clock.
        eventAction: ForegroundTaskEventAction.repeat(1000),
        // The CPU has to stay awake with the screen off; this is the wake lock
        // that matters, wakelock_plus only keeps the display on.
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
      ),
    );
    final result = await FlutterForegroundTask.startService(
      serviceId: recordingServiceId,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: notificationTitle,
      notificationText: '0.0 km · 00:00',
      callback: startRecordingCallback,
    );
    if (result is ServiceRequestFailure) {
      _detach();
      final opened = await store;
      await opened.clearState();
      throw RecordingException(result.error.toString());
    }
  }

  void _attach() {
    if (_listening) return;
    _listening = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  void _detach() {
    if (!_listening) return;
    _listening = false;
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
  }

  void _command(String command) =>
      FlutterForegroundTask.sendDataToTask(<String, Object?>{
        recordingMessageKind: recordingCommandMessage,
        recordingCommandKey: command,
      });

  void _onTaskData(Object data) {
    if (data is! Map) return;
    switch (data[recordingMessageKind]) {
      case recordingSnapshotMessage:
        publish(RecordingSnapshot.fromMap(data));
      case recordingStoppedMessage:
        if (_stopped?.isCompleted == false) _stopped!.complete();
    }
  }
}

/// The journal directory of the running app.
final recordingStoreProvider = Provider<Future<RecordingStore>>((ref) {
  final opening = RecordingStore.open();
  // A platform without `path_provider` — a widget test that forgot the
  // override — must fail where the store is used, not as an unhandled async
  // error somewhere else. Listening once here marks the failure as handled;
  // every `await` on the same future still sees it.
  unawaited(opening.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  return opening;
});

/// The recorder, picked for the platform the app is running on.
final recordingServiceProvider = Provider<RecordingService>((ref) {
  final service = defaultTargetPlatform == TargetPlatform.android
      ? ForegroundTaskRecordingService(
          store: ref.watch(recordingStoreProvider),
          rides: ref.watch(rideRepositoryProvider),
        )
      : MainIsolateRecordingService(
          store: ref.watch(recordingStoreProvider),
          rides: ref.watch(rideRepositoryProvider),
          positions: ref.watch(positionSourceProvider),
        );
  ref.onDispose(service.dispose);
  return service;
});
