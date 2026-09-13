import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:velorki_geo/velorki_geo.dart';

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

/// The handful of foreground-service calls the handler makes.
///
/// Behind an interface because all four are plugin statics that reach for a
/// platform channel: in a unit test there is none, so without this seam the
/// throttled notification, the snapshots sent to the UI and the stop
/// acknowledgement — the behaviour worth testing — could not be observed at
/// all.
abstract interface class ForegroundServiceHost {
  /// Stops the service, ending the notification with it.
  Future<void> stopService();

  /// Sends [data] to the UI isolate; a plain map, as the port only takes
  /// primitives.
  void sendDataToMain(Object data);

  /// Replaces the second line of the ongoing notification with [text].
  Future<void> updateNotificationText(String text);

  /// Brings the app back to the front when the rider taps the notification.
  void launchApp();
}

/// [ForegroundServiceHost] over the `FlutterForegroundTask` statics — the real
/// service, used everywhere outside the tests.
class FlutterForegroundServiceHost implements ForegroundServiceHost {
  /// Creates the host.
  const FlutterForegroundServiceHost();

  @override
  Future<void> stopService() => FlutterForegroundTask.stopService();

  @override
  void sendDataToMain(Object data) =>
      FlutterForegroundTask.sendDataToMain(data);

  @override
  Future<void> updateNotificationText(String text) =>
      FlutterForegroundTask.updateService(notificationText: text);

  @override
  void launchApp() => FlutterForegroundTask.launchApp();
}

/// The recorder, running inside the foreground service.
///
/// It owns the GPS stream, the journal and the statistics; the UI isolate only
/// renders the snapshots it sends and sends commands back. That split is what
/// keeps the ride going when the activity is destroyed.
class RecordingTaskHandler extends TaskHandler {
  /// Creates the handler.
  ///
  /// The arguments are the seams the tests need: every default is the
  /// expression the service isolate used to build inline, so the running app
  /// behaves exactly as before, while a test can hand in a temporary store, a
  /// fix stream it controls, a host that only records what it was asked and a
  /// clock that does not run — the notification throttle is measured in
  /// snapshot time, which without a fake clock would mean waiting out real
  /// seconds.
  RecordingTaskHandler({
    this.host = const FlutterForegroundServiceHost(),
    Future<RecordingStore> Function()? openStore,
    Stream<TrackPoint> Function()? fixes,
    DateTime Function()? clock,
  }) : _openStore = openStore ?? RecordingStore.open,
       _fixes =
           fixes ?? (() => recordingFixes(const GeolocatorPositionSource())),
       _clock = clock ?? DateTime.now;

  /// The foreground service this handler runs in.
  final ForegroundServiceHost host;

  final Future<RecordingStore> Function() _openStore;
  final Stream<TrackPoint> Function() _fixes;
  final DateTime Function() _clock;

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
    final store = await _openStore();
    final state = await store.readState();
    if (state == null) {
      // Nothing to record — the service was restarted without a ride.
      await host.stopService();
      return;
    }

    final existing = await store.readJournal(state.rideId);
    final journal = store.openJournal(state.rideId);
    await journal.open();

    final engine = RecordingEngine(
      store: store,
      journal: journal,
      initialState: state,
      fixes: _fixes(),
      ticks: _ticks.stream,
      clock: _clock,
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
    host.launchApp();
  }

  Future<void> _stopAndAcknowledge() async {
    await _stopEngine();
    host.sendDataToMain(<String, Object?>{
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
    unawaited(host.updateNotificationText(notificationTextFor(snapshot)));
  }

  void _send(RecordingSnapshot snapshot) =>
      host.sendDataToMain(snapshot.toMap());
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
