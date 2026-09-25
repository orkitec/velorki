import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/ride_stats.dart';
import '../domain/recording_snapshot.dart';
import '../domain/recording_state.dart';
import 'recording_journal.dart';

/// What the launch check found.
sealed class RecoveryResult {
  const RecoveryResult();
}

/// No recording was under way.
final class NoRecovery extends RecoveryResult {
  /// Creates the result.
  const NoRecovery();
}

/// A recording is still running in its foreground service; the UI only has to
/// listen again.
final class ReattachRecording extends RecoveryResult {
  /// Creates the result.
  const ReattachRecording(this.state);

  /// The recording that survived.
  final RecordingState state;
}

/// A recording was interrupted — the app was force-quit or the service was
/// killed. The rider decides whether to resume it or to finish it.
final class InterruptedRecording extends RecoveryResult {
  /// Creates the result.
  const InterruptedRecording({required this.state, required this.stats});

  /// The recording as the state file describes it.
  final RecordingState state;

  /// What is in the journal already.
  final RideStats stats;
}

/// Decides, once per launch, what to do with a leftover `recording_state.json`.
class RecoveryService {
  /// Creates a recovery check over [store].
  RecoveryService({required this.store, required this.isServiceRunning});

  /// Where the state file and the journals live.
  final RecordingStore store;

  /// Whether a recording service is alive right now.
  final Future<bool> Function() isServiceRunning;

  /// Reads the state file and classifies what it finds.
  ///
  /// A state file that says `paused` is treated like an interrupted recording:
  /// a paused ride whose service is gone still has to be resumed or finished
  /// by hand, and one whose service is alive is simply reattached.
  Future<RecoveryResult> checkOnLaunch() async {
    final state = await store.readState();
    if (state == null || state.status == RecordingStatus.idle) {
      return const NoRecovery();
    }
    if (await isServiceRunning()) return ReattachRecording(state);
    final points = await store.readJournal(state.rideId);
    return InterruptedRecording(
      state: state,
      // The seams of a continued ride are breaks here too, so the dialog
      // offers the figures the ride will actually be saved with.
      stats: computeRideStats(points, breaks: state.statsBreaks),
    );
  }
}

/// The launch check, run once and remembered.
///
/// `bootstrap()` kicks it off so the file system work happens while the first
/// frame is being built; the record tab awaits the same future through
/// [recordingRecoveryProvider], so the check never runs twice.
abstract final class RecordingRecovery {
  static Future<RecoveryResult>? _result;

  /// Runs the check, or returns the result of the run already in flight.
  static Future<RecoveryResult> checkOnLaunch() => _result ??= _run();

  /// Forgets the result, so the next call checks again. Used after a decision
  /// has been acted on, and by the tests.
  static void reset() => _result = null;

  /// Pins the result; the widget tests use this instead of the file system.
  @visibleForTesting
  static void overrideWith(Future<RecoveryResult> result) => _result = result;

  static Future<RecoveryResult> _run() async {
    try {
      final store = await RecordingStore.open();
      final service = RecoveryService(
        store: store,
        isServiceRunning: () async =>
            defaultTargetPlatform == TargetPlatform.android &&
            await FlutterForegroundTask.isRunningService,
      );
      return await service.checkOnLaunch();
    } on Object {
      // A recovery check must never keep the app from starting.
      return const NoRecovery();
    }
  }
}

/// What to do with a leftover recording, for the record tab.
final recordingRecoveryProvider = FutureProvider<RecoveryResult>(
  (ref) => RecordingRecovery.checkOnLaunch(),
);

/// Whether the launch's leftover recording has been dealt with: reattached,
/// or resumed, finished or discarded from the dialog. Stays `false` when
/// there was none, which [waitForRecovery] reads as nothing to wait for.
final recoverySettledProvider = NotifierProvider<RecoverySettled, bool>(
  RecoverySettled.new,
);

/// See [recoverySettledProvider].
class RecoverySettled extends Notifier<bool> {
  @override
  bool build() => false;

  /// The recovery has been dealt with.
  void settle() => state = true;
}

/// Completes once whatever the launch found of an unfinished ride has been
/// dealt with, at once when there was nothing.
///
/// A file or a shared link that opened the app waits for this, so its
/// preview comes after the rider has answered for the ride, not over the
/// question, and neither is lost.
Future<void> waitForRecovery(ProviderContainer container) async {
  final result = await container.read(recordingRecoveryProvider.future);
  if (result is NoRecovery || container.read(recoverySettledProvider)) return;
  final settled = Completer<void>();
  final subscription = container.listen<bool>(recoverySettledProvider, (
    _,
    next,
  ) {
    if (next && !settled.isCompleted) settled.complete();
  });
  try {
    await settled.future;
  } finally {
    subscription.close();
  }
}
