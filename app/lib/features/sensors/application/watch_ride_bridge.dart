import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../navigation/application/navigation_controller.dart';
import '../../recording/application/recording_controller.dart';
import '../../recording/application/ride_finish_request.dart';
import '../../recording/application/ride_notification_updater.dart';
import '../../settings/data/appearance_controller.dart';
import '../../settings/data/units.dart';
import '../data/sensor_settings.dart';
import '../data/watch_gateway.dart';
import '../data/watch_protocol.dart';
import '../data/watch_sensor_source.dart';
import 'sensor_hub.dart';

part 'watch_ride_bridge.g.dart';

final Logger _log = Logger('velorki.sensors.watch');

/// The clock the context throttle is measured against.
///
/// A provider so tests can wind it forward without waiting out real seconds,
/// the same reason the notification has one.
@Riverpod(keepAlive: true)
DateTime Function() watchClock(Ref ref) => DateTime.now;

/// Everything that passes between the phone and the watch app while the
/// "Apple Watch" switch is on.
///
/// The watch is a display and a sensor, never a second recorder. It sends what
/// it measures and what the rider taps; the phone's recorder does the work and
/// reports back what it has done. So there are three jobs here, and they all
/// end the moment the switch goes off:
///
///  * the watch's heart rate is registered with the hub as a source, where it
///    outranks the health store (see [WatchSensorSource]);
///  * the figures the lock screen shows are pushed to the wrist as the
///    application context — the latest picture wins, at most every
///    [watchContextThrottle], and straight away when the ride's status or a
///    cue changes;
///  * the buttons on the wrist drive the recorder, and a ride starting or
///    ending asks the watch to start or end its own workout session.
///
/// Kept alive and read once in `bootstrap()`, exactly like the sensor sources
/// controller: a provider nobody reads is one that never exists, and then it
/// observes nothing.
/// Counts the rides the watch has started, for whoever wants to react —
/// the app brings the Record tab up, so the phone taken out of the pocket
/// shows the ride rather than the planner it was left on.
@Riverpod(keepAlive: true)
class WatchRideStarts extends _$WatchRideStarts {
  @override
  int build() => 0;

  /// One more ride started from the wrist.
  void bump() => state++;
}

@Riverpod(keepAlive: true)
class WatchRideBridge extends _$WatchRideBridge {
  WatchGateway? _gateway;
  WatchSensorSource? _source;
  StreamSubscription<Map<String, Object?>>? _messages;

  /// The work queued so far, so two changes in quick succession are applied
  /// in order rather than racing each other. Tests await it.
  Future<void> _pending = Future<void>.value();

  /// The context the watch is showing, `null` while nothing was pushed.
  Map<String, Object?>? _context;

  /// When that context went out, for the throttle.
  DateTime? _contextAt;

  /// Whether the watch was asked to measure, so it is asked to stop exactly
  /// once and never asked to stop something it never started.
  bool _measuring = false;

  /// When the watch last reported a heart rate, and when the phone last
  /// launched the watch app to get one: the watchdog behind [_watchdog].
  DateTime? _lastReadingAt;
  DateTime? _lastLaunchAt;

  /// Whether a ride was running on the previous pass.
  bool _riding = false;

  @override
  void build() {
    ref.listen(sensorSettingsProvider, (previous, next) => _schedule());
    ref.listen(recordingControllerProvider, (previous, next) => _schedule());
    ref.listen(navigationControllerProvider, (previous, next) => _schedule());
    ref.listen(navigationCueProvider, (previous, next) => _schedule());
    ref.listen(unitSystemProvider, (previous, next) => _schedule());
    ref.listen(appearanceSettingProvider, (previous, next) => _schedule());
    ref.onDispose(_shutdown);
    _schedule();
  }

  /// Resolves once everything asked for so far has been applied. Only the
  /// tests need this; the app is happy to let it run.
  Future<void> get settled => _pending;

  void _schedule([Future<void> Function()? work]) {
    _pending = _pending
        .then((_) => (work ?? _sync)())
        .catchError(
          (Object error, StackTrace stackTrace) =>
              _log.warning('watch bridge failed', error, stackTrace),
        );
  }

  Future<void> _sync() async {
    final gateway = ref.read(watchGatewayProvider);
    if (gateway == null || !ref.read(sensorSettingsProvider).watch) {
      await _detach();
      return;
    }
    _attach(gateway);
    await _followRide(gateway);
    await _watchdog(gateway);
    await _pushContext(gateway);
  }

  /// Launches the watch app again when its readings stop mid-ride.
  ///
  /// A watch app that watchOS suspended, or that the rider closed, hears no
  /// message; HealthKit's launch reaches it anyway. Only while the ride is
  /// running, not paused, and not more than once every [watchRelaunchGap].
  Future<void> _watchdog(WatchGateway gateway) async {
    final recording = ref.read(recordingControllerProvider);
    if (!recording.isRecording || recording.isPaused || !_measuring) return;
    final now = ref.read(watchClockProvider)();
    final since = _lastReadingAt ?? _lastLaunchAt;
    if (since == null || now.difference(since) < watchSilence) return;
    final launched = _lastLaunchAt;
    if (launched != null && now.difference(launched) < watchRelaunchGap) {
      return;
    }
    _lastLaunchAt = now;
    _log.info('the watch fell silent; launching its app again');
    if (await gateway.isReachable()) {
      await _sendWorkout(gateway, start: true);
    } else {
      await gateway.launchWorkout();
    }
  }

  /// Registers the watch with the hub and starts listening to the wrist.
  void _attach(WatchGateway gateway) {
    if (_source != null) return;
    _gateway = gateway;
    final source = WatchSensorSource(gateway: gateway)..start();
    _source = source;
    ref.read(sensorHubProvider.notifier).register(source);
    // The source takes the readings off this same stream; the bridge only
    // wants the rest of what the watch says.
    _messages = gateway.messages.listen(_onMessage);
  }

  /// Gives the watch back: the source goes, and a workout that is still
  /// running on the wrist is ended rather than left measuring for nothing.
  Future<void> _detach() async {
    final source = _source;
    if (source == null) return;
    _source = null;
    await _messages?.cancel();
    _messages = null;
    ref.read(sensorHubProvider.notifier).unregister(source.id);
    await source.dispose();
    final gateway = _gateway;
    if (gateway != null && _measuring) {
      _measuring = false;
      await _sendWorkout(gateway, start: false);
    }
    _gateway = null;
    _context = null;
    _contextAt = null;
    _riding = false;
  }

  /// Asks the watch to measure while a ride runs, and to stop when it ends.
  Future<void> _followRide(WatchGateway gateway) async {
    final riding = ref.read(recordingControllerProvider).isRecording;
    if (riding == _riding) return;
    _riding = riding;
    if (riding) {
      if (_measuring) return;
      // A watch whose app is not running cannot be sent a message; HealthKit
      // can launch the app into a workout instead, and the session starts
      // there. Either way the stop at the end of the ride is owed.
      _lastReadingAt = null;
      _lastLaunchAt = ref.read(watchClockProvider)();
      if (await gateway.isReachable()) {
        _measuring = true;
        await _sendWorkout(gateway, start: true);
      } else if (await gateway.launchWorkout()) {
        _measuring = true;
      }
      return;
    }
    if (!_measuring) return;
    _measuring = false;
    await _sendWorkout(gateway, start: false);
  }

  Future<void> _sendWorkout(WatchGateway gateway, {required bool start}) =>
      gateway.sendMessage(<String, Object?>{
        watchTypeKey: watchWorkoutType,
        watchWorkoutActionKey: start ? watchWorkoutStart : watchWorkoutStop,
      });

  /// Pushes the figures, as far as the throttle allows.
  Future<void> _pushContext(WatchGateway gateway) async {
    final data = _contextData();
    final previous = _context;
    if (mapEquals(data, previous)) return;
    // The status and a cue are what the rider is waiting for, and a new
    // accent is what they are looking at; the figures can wait for the next
    // window.
    final urgent =
        previous == null ||
        data[watchStatusKey] != previous[watchStatusKey] ||
        data[watchCueKey] != previous[watchCueKey] ||
        data[watchAccentKey] != previous[watchAccentKey];
    final now = ref.read(watchClockProvider)();
    final sentAt = _contextAt;
    if (!urgent &&
        sentAt != null &&
        now.difference(sentAt) < watchContextThrottle) {
      return;
    }
    _context = data;
    _contextAt = now;
    await gateway.updateApplicationContext(data);
  }

  /// What the watch's screen is drawn from.
  Map<String, Object?> _contextData() {
    final cue = ref.read(navigationCueProvider);
    final cueAt = cue?.millisecondsSinceEpoch ?? 0;
    final accent = _hex(ref.read(appearanceSettingProvider).accent.dark);
    final recording = ref.read(recordingControllerProvider);
    final snapshot = recording.snapshot;
    if (!recording.isRecording || snapshot == null) {
      return <String, Object?>{
        watchStatusKey: watchStatusIdle,
        watchDistanceKey: '',
        watchElapsedKey: '',
        watchSpeedKey: '',
        watchTurnIconKey: '',
        watchTurnLabelKey: '',
        watchTurnDistanceKey: '',
        watchOffRouteKey: false,
        watchCueKey: cueAt,
        watchAccentKey: accent,
      };
    }
    final progress = ref.read(navigationControllerProvider);
    // The lock screen's own map: the same figures, already formatted in the
    // rider's units and language, because the phone knows both and the watch
    // app knows neither. Its keys are its own, so they are spelled out here
    // rather than assumed to be the watch's.
    final activity = rideActivityData(
      ref.read(navigationLocalizationsProvider),
      ref.read(unitSystemProvider),
      snapshot,
      progress,
    );
    return <String, Object?>{
      watchStatusKey: recording.isPaused
          ? watchStatusPaused
          : watchStatusActive,
      watchDistanceKey: activity['distance'] ?? '',
      watchElapsedKey: activity['elapsed'] ?? '',
      watchSpeedKey: activity['speed'] ?? '',
      watchTurnIconKey: activity['turnIcon'] ?? '',
      watchTurnLabelKey: activity['turnLabel'] ?? '',
      watchTurnDistanceKey: activity['turnDistance'] ?? '',
      watchOffRouteKey:
          (progress?.offRoute ?? false) || progress?.guidance != null,
      watchCueKey: cueAt,
      watchAccentKey: accent,
    };
  }

  /// `#RRGGBB`, the alpha dropped: the watch fills it in as opaque.
  static String _hex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// The container is going: the source is closed and the wrist is left
  /// alone. Nothing is unregistered and nothing is sent, because the hub is
  /// on its way out too and `ref` may not be read from here.
  void _shutdown() {
    final source = _source;
    _source = null;
    _gateway = null;
    unawaited(_messages?.cancel());
    _messages = null;
    if (source != null) unawaited(source.dispose());
  }

  void _onMessage(Map<String, Object?> message) {
    switch (message[watchTypeKey]) {
      case watchHeartRateType:
        _lastReadingAt = ref.read(watchClockProvider)();
      case watchCommandType:
        _schedule(() => _command(message[watchCommandKey]));
      case watchHeartRateStoppedType:
        // The rider ended the workout on the wrist to save its battery. The
        // source simply falls silent; the hub hands the heart rate back to
        // whatever else is reporting once the last reading is stale.
        _measuring = false;
        ref.read(sensorHubProvider.notifier).refresh();
    }
  }

  /// Does what the button on the wrist asked for.
  ///
  /// Every one of them is the recorder's own call, so a ride steered from the
  /// watch is the same ride as one steered from the phone — down to the
  /// notification the foreground service carries.
  Future<void> _command(Object? command) async {
    final recording = ref.read(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);
    switch (command) {
      case watchCommandStart:
        if (recording.isRecording) return;
        // None of the asking the record screen does before a ride — the
        // location prompt, the notification prompt — can be done from here:
        // they are system sheets on the phone, which is in a pocket. A
        // recorder that refuses simply never reports a ride, and the watch
        // goes on showing "idle".
        final l10n = ref.read(navigationLocalizationsProvider);
        await controller.start(
          notificationTitle: l10n.recordingNotificationTitle,
        );
        // Counted whether or not the recorder agreed: a recorder that
        // refused has its reason on the Record tab, which is where the
        // phone goes.
        ref.read(watchRideStartsProvider.notifier).bump();
        // A phone in a pocket is told, so a tap brings the app up: a ride
        // started from the wrist with the app closed gets no GPS on iOS
        // until the app has been in front once.
        final gateway = _gateway;
        if (gateway != null) {
          await gateway.notifyRideStarted(
            title: l10n.watchRideStartedTitle,
            body: l10n.watchRideStartedBody,
          );
        }
      case watchCommandPause:
        if (!recording.isRecording || recording.isPaused) return;
        await controller.pause();
      case watchCommandResume:
        if (!recording.isPaused) return;
        await controller.resume();
      case watchCommandStop:
        if (!recording.isRecording) return;
        // The ride cannot be saved from the wrist: it is named on a sheet,
        // and the sheet also offers to carry on. So the recording is put
        // down here — the rider has stopped riding — and the record screen
        // opens that sheet the moment the phone is looked at again.
        if (!recording.isPaused) await controller.pause();
        ref.read(rideFinishRequestProvider.notifier).raise();
    }
  }
}

/// How long the watch may go without a reading mid-ride before the phone
/// launches its app again.
const Duration watchSilence = Duration(seconds: 45);

/// The least time between two such launches.
const Duration watchRelaunchGap = Duration(minutes: 2);
