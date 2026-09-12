import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../map/data/position_provider.dart';
import '../domain/recording_snapshot.dart';
import 'recording_engine.dart';
import 'recording_journal.dart';
import 'recording_positions.dart';

/// Entry point of the Android foreground service isolate.
///
/// Has to be a top-level function with the `vm:entry-point` pragma, otherwise
/// tree shaking removes it from the release build and the service starts into
/// nothing.
@pragma('vm:entry-point')
void startRecordingCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

/// The recorder, running inside the foreground service.
///
/// It owns the GPS stream, the journal and the statistics; the UI isolate only
/// renders the snapshots it sends and sends commands back. That split is what
/// keeps the ride going when the activity is destroyed.
class RecordingTaskHandler extends TaskHandler {
  RecordingEngine? _engine;
  StreamSubscription<RecordingSnapshot>? _snapshots;
  final StreamController<DateTime> _ticks =
      StreamController<DateTime>.broadcast();
  DateTime _lastNotification = DateTime.fromMillisecondsSinceEpoch(0);

  /// Seconds between two notification updates. The rider glances at it; one
  /// redraw per second would only cost battery.
  static const Duration notificationInterval = Duration(seconds: 5);

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final store = await RecordingStore.open();
    final state = await store.readState();
    if (state == null) {
      // Nothing to record — the service was restarted without a ride.
      await FlutterForegroundTask.stopService();
      return;
    }

    final existing = await store.readJournal(state.rideId);
    final journal = store.openJournal(state.rideId);
    await journal.open();

    final engine = RecordingEngine(
      store: store,
      journal: journal,
      initialState: state,
      fixes: recordingFixes(const GeolocatorPositionSource()),
      ticks: _ticks.stream,
    )..seed(existing);
    _snapshots = engine.snapshots.listen(_onSnapshot);
    await engine.start();
    _engine = engine;
  }

  @override
  void onRepeatEvent(DateTime timestamp) => _ticks.add(timestamp);

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _stopEngine();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final command = data[recordingCommandKey];
    final engine = _engine;
    switch (command) {
      case recordingCommandPause:
        if (engine != null) unawaited(engine.pause());
      case recordingCommandResume:
        if (engine != null) unawaited(engine.resume());
      case recordingCommandSync:
        if (engine != null) _send(engine.snapshot);
      case recordingCommandStop:
        unawaited(_stopAndAcknowledge());
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  Future<void> _stopAndAcknowledge() async {
    await _stopEngine();
    FlutterForegroundTask.sendDataToMain(<String, Object?>{
      recordingMessageKind: recordingStoppedMessage,
    });
  }

  Future<void> _stopEngine() async {
    final engine = _engine;
    _engine = null;
    await _snapshots?.cancel();
    _snapshots = null;
    await engine?.stop();
    if (!_ticks.isClosed) await _ticks.close();
  }

  void _onSnapshot(RecordingSnapshot snapshot) {
    _send(snapshot);
    final now = snapshot.startedAt.add(snapshot.elapsed);
    if (now.difference(_lastNotification) < notificationInterval) return;
    _lastNotification = now;
    unawaited(
      FlutterForegroundTask.updateService(
        notificationText: notificationTextFor(snapshot),
      ),
    );
  }

  void _send(RecordingSnapshot snapshot) =>
      FlutterForegroundTask.sendDataToMain(snapshot.toMap());
}

/// The second line of the recording notification: distance and time.
///
/// Formatted here rather than with the app's localisations because the service
/// isolate has no `BuildContext` and no locale; the units are the metric ones
/// the rest of the app uses.
String notificationTextFor(RecordingSnapshot snapshot) {
  final kilometers = (snapshot.distanceM / 1000).toStringAsFixed(1);
  final seconds = snapshot.elapsed.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = hours > 0
      ? '$hours:${two(minutes)}:${two(rest)}'
      : '${two(minutes)}:${two(rest)}';
  final suffix = snapshot.status == RecordingStatus.paused ? ' · ⏸' : '';
  return '$kilometers km · $clock$suffix';
}
