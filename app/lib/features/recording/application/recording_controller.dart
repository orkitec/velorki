import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../data/recording_service.dart';
import '../data/recording_settings.dart';
import '../domain/follow_choice.dart';
import '../domain/gps_precision.dart';
import '../domain/recording_snapshot.dart';
import '../domain/recording_state.dart';
import '../domain/ride.dart';

/// What the record tab draws.
@immutable
class RecordingUiState {
  /// Creates the state.
  const RecordingUiState({
    this.snapshot,
    this.track = const <LatLng>[],
    this.busy = false,
    this.follow = FollowChoice.plan,
    this.followChosen = false,
  });

  /// The latest snapshot, `null` while nothing is being recorded.
  final RecordingSnapshot? snapshot;

  /// The track so far, grown one snapshot at a time rather than resent.
  final List<LatLng> track;

  /// Whether a start or stop is in flight, so the buttons can be disabled.
  final bool busy;

  /// What the next ride follows. The plan by default: a rider who planned a
  /// route and moves to Record wants to ride it, and without a plan the
  /// plan is nothing.
  final FollowChoice follow;

  /// Whether [follow] was picked by the rider in the picker this session.
  /// Until then the tab may suggest one from where the rider came.
  final bool followChosen;

  /// The saved route [follow] names, or `null` for the plan or no route.
  String? get followedRouteId => follow.routeId;

  /// Whether a ride is being recorded, paused or not.
  bool get isRecording => snapshot?.status.isRecording ?? false;

  /// Whether the recorder is paused, by the rider or by auto-pause.
  bool get isPaused => snapshot?.status == RecordingStatus.paused;

  /// A copy with the given fields replaced.
  RecordingUiState copyWith({
    RecordingSnapshot? snapshot,
    List<LatLng>? track,
    bool? busy,
    FollowChoice? follow,
    bool? followChosen,
    bool clearSnapshot = false,
  }) => RecordingUiState(
    snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
    track: track ?? this.track,
    busy: busy ?? this.busy,
    follow: follow ?? this.follow,
    followChosen: followChosen ?? this.followChosen,
  );
}

/// Drives the recorder from the UI and keeps the track line for the map.
///
/// Everything that talks to the platform lives in [RecordingService]; this
/// class only decides what the screen sees, which is what makes the widget
/// tests a matter of handing in a fake service.
class RecordingController extends Notifier<RecordingUiState> {
  StreamSubscription<RecordingSnapshot>? _subscription;

  @override
  RecordingUiState build() {
    final service = ref.watch(recordingServiceProvider);
    _subscription = service.snapshots.listen(_onSnapshot);
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    final last = service.lastSnapshot;
    return RecordingUiState(
      snapshot: last,
      track: last?.lastPosition == null
          ? const <LatLng>[]
          : <LatLng>[last!.lastPosition!],
    );
  }

  RecordingService get _service => ref.read(recordingServiceProvider);

  /// The GPS profile the next ride runs at: what the rider picked, or the
  /// saver profile when the battery saver overrules it. Read at the moment a
  /// ride starts, because that is when the stream is opened — changing it
  /// mid-ride would mean restarting the recorder.
  GpsPrecision get _precision =>
      ref.read(recordingSettingsProvider).effectivePrecision;

  /// The rider's own pick in the picker: kept until the app restarts,
  /// whatever tab they arrive from later.
  void choose(FollowChoice choice) =>
      state = state.copyWith(follow: choice, followChosen: true);

  /// What the Record tab proposes on being arrived at: the route on the
  /// library card the rider came from, or the plan they came from. Taken
  /// only while no ride runs and the rider has not picked for themselves;
  /// `null` proposes nothing and leaves the choice as it is.
  void suggest(FollowChoice? choice) {
    if (choice == null || state.isRecording || state.followChosen) return;
    state = state.copyWith(follow: choice);
  }

  /// The choice a ride that is already under way was started with: its saved
  /// route, or the plan when it has none, which is what a ride without a
  /// route link followed before it was interrupted.
  static FollowChoice _followOf(String? routeId) =>
      routeId == null ? FollowChoice.plan : FollowSaved(routeId);

  /// Starts a ride.
  ///
  /// Throws [RecordingException] when the platform refused to start the
  /// recorder; the caller shows the message.
  Future<void> start({required String notificationTitle}) async {
    if (state.isRecording || state.busy) return;
    state = state.copyWith(busy: true, track: const <LatLng>[]);
    _listening = true;
    try {
      await _service.start(
        notificationTitle: notificationTitle,
        routeId: state.followedRouteId,
        precision: _precision,
      );
    } catch (_) {
      _listening = false;
      rethrow;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Suspends the recording.
  Future<void> pause() => _service.pause();

  /// Continues the recording.
  Future<void> resume() => _service.resume();

  /// Finishes the ride; returns `null` when too little was recorded to keep.
  Future<Ride?> stop({required String rideName}) async {
    if (state.busy) return null;
    state = state.copyWith(busy: true);
    _listening = false;
    try {
      return await _service.stop(rideName: rideName);
    } finally {
      // Whatever the recorder answered, the ride is over for the screen:
      // a live panel that cannot be left is worse than a lost snapshot. The
      // route choice outlives the ride.
      state = _afterRide();
    }
  }

  /// Stops the recorder without saving anything, and hands back the recording
  /// that is now waiting for a name; `null` when nothing was recorded.
  ///
  /// Finishing a ride is two steps, because the rider names it in between:
  /// this ends the recording, [finishInterrupted] then writes the row with the
  /// name they typed and [discardInterrupted] throws the whole thing away. The
  /// state stays busy in between, so the panel under the sheet is inert.
  Future<RecordingState?> halt() async {
    if (state.busy) return null;
    state = state.copyWith(busy: true);
    _listening = false;
    final RecordingState? recording;
    try {
      recording = await _service.halt();
    } on Object {
      state = state.copyWith(busy: false);
      _listening = true;
      rethrow;
    }
    if (recording == null) state = _afterRide();
    return recording;
  }

  /// Where the recording [rideId] began and where it ended, read back out of
  /// the journal, or `null` when it holds too little to become a ride.
  ///
  /// What the default ride name is built from: the journal is the truth for
  /// both a ride that has just been stopped and one recovered on relaunch.
  /// The two-fix floor is the one the recorder saves by, so a `null` here is
  /// also the answer to "is this worth naming at all".
  Future<({LatLng start, LatLng end})?> trackEnds(String rideId) async {
    final points = await _journalTrack(rideId);
    if (points.length < 2) return null;
    return (start: points.first, end: points.last);
  }

  /// Listens to a recorder that outlived the UI and puts its track back on the
  /// map. Returns whether one was still running.
  Future<bool> reattach(RecordingState recording) async {
    final running = await _service.reattach();
    if (!running) return false;
    _listening = true;
    state = state.copyWith(
      track: await _journalTrack(recording.rideId),
      follow: _followOf(recording.routeId),
    );
    return true;
  }

  /// Continues an interrupted recording where it left off.
  Future<void> resumeInterrupted(
    RecordingState recording, {
    required String notificationTitle,
  }) async {
    state = state.copyWith(busy: true, follow: _followOf(recording.routeId));
    _listening = true;
    try {
      // The recorder first: every second spent reading the journal back is a
      // second of the ride that is not being recorded.
      await _service.resumeInterrupted(
        recording,
        notificationTitle: notificationTitle,
        precision: _precision,
      );
      state = state.copyWith(track: await _journalTrack(recording.rideId));
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Records onto the already saved ride [ride] again, continuing its track
  /// and its figures.
  ///
  /// The recorder does the work of handing the ride back to itself; here it is
  /// the same as resuming an interrupted recording, down to putting the track
  /// that is already in the journal back on the map.
  Future<void> continueRide(
    Ride ride, {
    required String notificationTitle,
  }) async {
    if (state.isRecording || state.busy) return;
    state = state.copyWith(busy: true, follow: _followOf(ride.routeId));
    _listening = true;
    try {
      await _service.continueRide(
        ride,
        notificationTitle: notificationTitle,
        precision: _precision,
      );
      state = state.copyWith(track: await _journalTrack(ride.id));
    } catch (_) {
      _listening = false;
      rethrow;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Turns an interrupted recording into a ride without continuing it.
  Future<Ride?> finishInterrupted(
    RecordingState recording, {
    required String rideName,
  }) async {
    final ride = await _service.finishInterrupted(
      recording,
      rideName: rideName,
    );
    state = _afterRide();
    return ride;
  }

  /// Throws an interrupted recording away.
  Future<void> discardInterrupted(RecordingState recording) async {
    await _service.discardInterrupted(recording);
    state = _afterRide();
  }

  /// The idle state after a ride: nothing recorded, the route choice kept.
  RecordingUiState _afterRide() =>
      RecordingUiState(follow: state.follow, followChosen: state.followChosen);

  // Whether snapshots from the recorder are wanted. On by default, so a
  // recorder that outlived the UI shows up as soon as it reports; off after
  // `stop`, so a last flush from the foreground isolate cannot bring the
  // live panel back for a ride that is already saved; on again when a ride
  // starts or a running recorder is found.
  bool _listening = true;

  void _onSnapshot(RecordingSnapshot snapshot) {
    if (!snapshot.status.isRecording) {
      state = state.copyWith(clearSnapshot: true);
      return;
    }
    if (!_listening) return;
    state = state.copyWith(
      snapshot: snapshot,
      track: snapshot.newPoints.isEmpty
          ? state.track
          : <LatLng>[...state.track, ...snapshot.newPoints],
    );
  }

  Future<List<LatLng>> _journalTrack(String rideId) async {
    final store = await ref.read(recordingStoreProvider);
    final points = await store.readJournal(rideId);
    return points.map((p) => p.pos).toList(growable: false);
  }
}

/// The record tab's state.
final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingUiState>(
      RecordingController.new,
    );
