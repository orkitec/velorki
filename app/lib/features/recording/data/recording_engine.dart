import 'dart:async';

import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/geo/ride_stats.dart';
import '../domain/recording_snapshot.dart';
import '../domain/recording_state.dart';
import '../domain/ride.dart';
import 'recording_journal.dart';

/// The recorder itself: fixes in, journal and statistics out.
///
/// Pure Dart with no plugin of its own, because it has to run in two very
/// different places: inside the Android foreground-service isolate, and in the
/// main isolate on iOS. Everything platform-shaped — where the fixes come
/// from, what drives the one-second tick — is injected, which is also what
/// makes it testable with a list of synthetic positions.
class RecordingEngine {
  /// Creates an engine for the recording described by [initialState].
  RecordingEngine({
    required this.store,
    required this.journal,
    required RecordingState initialState,
    required this.fixes,
    required this.ticks,
    DateTime Function()? clock,
    this.autoPauseAfter = const Duration(seconds: 10),
    this.autoPause = true,
    RideStatsAccumulator? accumulator,
  }) : _state = initialState,
       _clock = clock ?? DateTime.now,
       _accumulator = accumulator ?? RideStatsAccumulator();

  /// Where the state file lives; it is rewritten on every state change.
  final RecordingStore store;

  /// The journal the accepted fixes are appended to.
  final RecordingJournal journal;

  /// How long the rider has to stand still before the recording pauses itself.
  final Duration autoPauseAfter;

  /// Whether auto-pause is armed at all.
  final bool autoPause;

  /// The fixes to record.
  final Stream<TrackPoint> fixes;

  /// One event per second; on Android it is the foreground service's repeat
  /// event, so the clock keeps ticking with the screen off.
  final Stream<DateTime> ticks;

  final DateTime Function() _clock;
  final RideStatsAccumulator _accumulator;
  final StreamController<RecordingSnapshot> _snapshots =
      StreamController<RecordingSnapshot>.broadcast();

  RecordingState _state;
  StreamSubscription<TrackPoint>? _fixSubscription;
  StreamSubscription<DateTime>? _tickSubscription;
  final List<LatLng> _pending = <LatLng>[];
  DateTime? _lastMovementAt;
  double _speedMps = 0;
  TrackPoint? _lastPoint;
  bool _autoPaused = false;
  bool _stopped = false;

  /// One snapshot per tick, plus one on every state change.
  Stream<RecordingSnapshot> get snapshots => _snapshots.stream;

  /// The recording this engine is driving.
  RecordingState get state => _state;

  /// Whether the recorder is active or paused.
  RecordingStatus get status => _state.status;

  /// Whether the pause was triggered by standing still rather than by the
  /// rider.
  bool get isAutoPaused => _autoPaused;

  /// The statistics as they stand.
  RideStats get stats => _accumulator.stats;

  /// The latest snapshot, without waiting for the next tick.
  RecordingSnapshot get snapshot => _snapshot(const <LatLng>[]);

  /// Folds fixes that are already in the journal back in, so a resumed ride
  /// continues its statistics instead of starting from zero.
  ///
  /// Must be called before [start] and never journals anything.
  void seed(List<TrackPoint> points) {
    for (final point in points) {
      if (_accumulator.add(point)) _lastPoint = point;
    }
    _lastMovementAt = _accumulator.lastMovingAt ?? _clock();
  }

  /// Subscribes to the fixes and to the tick.
  Future<void> start() async {
    if (_stopped) throw StateError('the recording engine was already stopped');
    _lastMovementAt ??= _clock();
    _fixSubscription = fixes.listen(_onFix, onError: (Object _) {});
    _tickSubscription = ticks.listen(_onTick);
    await _writeState();
    _emit();
  }

  /// Stops journalling until [resume]; fixes that arrive meanwhile are
  /// dropped, which is what makes the break show up as a gap in the journal.
  Future<void> pause() async {
    if (_stopped || _state.status == RecordingStatus.paused) return;
    _autoPaused = false;
    await _setPaused();
  }

  /// Continues journalling after [pause] or after an auto-pause.
  Future<void> resume() async {
    if (_stopped || _state.status == RecordingStatus.active) return;
    _autoPaused = false;
    _lastMovementAt = _clock();
    _state = _state.copyWith(
      status: RecordingStatus.active,
      pauses: _closeLastPause(),
    );
    await _writeState();
    _emit();
  }

  /// Finishes the recording: unsubscribes, flushes and closes the journal.
  ///
  /// The state file is deliberately left behind — only writing the `rides` row
  /// may remove it, so a crash between here and the database still recovers.
  Future<RideStats> stop() async {
    if (_stopped) return _accumulator.stats;
    _stopped = true;
    await _fixSubscription?.cancel();
    await _tickSubscription?.cancel();
    _fixSubscription = null;
    _tickSubscription = null;
    await journal.close();
    _state = _state.copyWith(pauses: _closeLastPause());
    await _writeState();
    _emit(status: RecordingStatus.idle);
    await _snapshots.close();
    return _accumulator.stats;
  }

  void _onFix(TrackPoint fix) {
    if (_stopped) return;
    // A manual pause drops fixes outright; an auto-pause keeps listening,
    // because moving again is the only way out of it.
    if (_state.status == RecordingStatus.paused && !_autoPaused) return;
    if (!_accumulator.add(fix)) return;
    unawaited(journal.append(fix));
    _lastPoint = fix;
    _pending.add(fix.pos);
    _speedMps = _accumulator.lastSegmentSpeedMps;
    if (_speedMps >= movingSpeedThresholdMps) {
      _lastMovementAt = _clock();
      if (_autoPaused) unawaited(resume());
    }
  }

  void _onTick(DateTime now) {
    if (_stopped) return;
    if (_state.status == RecordingStatus.active && autoPause) {
      final since = _lastMovementAt ?? now;
      if (now.difference(since) >= autoPauseAfter) {
        _speedMps = 0;
        _autoPaused = true;
        unawaited(_setPaused());
        return;
      }
    }
    // With a five-metre distance filter a standing rider produces no fixes at
    // all, so the displayed speed has to decay on its own.
    if (_state.status == RecordingStatus.paused) _speedMps = 0;
    _emit();
  }

  Future<void> _setPaused() async {
    _state = _state.copyWith(
      status: RecordingStatus.paused,
      pauses: <RidePause>[
        ..._closeLastPause(),
        RidePause(startedAt: _clock().toUtc()),
      ],
    );
    await journal.flush();
    await _writeState();
    _emit();
  }

  List<RidePause> _closeLastPause() {
    final pauses = _state.pauses;
    if (pauses.isEmpty || pauses.last.endedAt != null) return pauses;
    return <RidePause>[
      ...pauses.take(pauses.length - 1),
      pauses.last.ending(_clock().toUtc()),
    ];
  }

  /// State writes are serialised: a tick (auto-pause) and a fix (resume) can
  /// both request one in the same event loop turn, and two concurrent
  /// temp-file renames would race. Each write captures the state as it was
  /// when requested, so the last write always reflects the latest state.
  Future<void> _pendingWrite = Future<void>.value();

  Future<void> _writeState() {
    final state = _state;
    _pendingWrite = _pendingWrite
        .catchError((Object _) {})
        .then((_) => store.writeState(state));
    return _pendingWrite;
  }

  void _emit({RecordingStatus? status}) {
    final points = _pending.isEmpty
        ? const <LatLng>[]
        : List<LatLng>.unmodifiable(_pending);
    _pending.clear();
    final snapshot = _snapshot(points, status: status);
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }

  RecordingSnapshot _snapshot(
    List<LatLng> newPoints, {
    RecordingStatus? status,
  }) => RecordingSnapshot.fromStats(
    rideId: _state.rideId,
    status: status ?? _state.status,
    startedAt: _state.startedAt,
    stats: _accumulator.stats,
    elapsed: _clock().toUtc().difference(_state.startedAt.toUtc()),
    autoPaused: _autoPaused,
    speedMps: _speedMps,
    lastPoint: _lastPoint,
    newPoints: newPoints,
  );
}
