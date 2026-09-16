import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../navigation/application/navigation_controller.dart';
import '../../navigation/domain/navigation_progress.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../data/live_activity.dart';
import '../data/notification_updater.dart';
import '../domain/recording_snapshot.dart';
import '../presentation/recording_format.dart';
import 'recording_controller.dart';

/// At most one notification update this often. The rider glances at the
/// notification; a redraw per fix would only cost battery.
const Duration notificationThrottle = Duration(seconds: 2);

/// At most one live-activity update this often. ActivityKit budgets updates,
/// so the lock screen is written half as often as the notification.
const Duration liveActivityThrottle = Duration(seconds: 5);

/// How long each notification update tells the service isolate to keep its
/// hands off the text. Comfortably longer than [notificationThrottle], so a
/// running UI always renews in time, and short enough that a UI that was
/// destroyed hands the text back within a few seconds.
const Duration notificationLease = Duration(seconds: 10);

/// The clock the throttles are measured against.
///
/// A provider so tests can wind it forward without waiting out real seconds.
final rideNotificationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Writes what a ride is doing onto the lock screen: the Android ongoing
/// notification and the iOS live activity, both from the main isolate.
///
/// It is the main isolate that knows about turn-by-turn — the recording
/// service isolate has no navigator — so the richer line has to be written
/// from here. Kept alive for the whole session and read once by `HomeShell`,
/// exactly like [NavigationController], because a provider nobody reads is a
/// provider that never exists.
class RideNotificationUpdater extends Notifier<void> {
  /// The two writers, held rather than looked up every time: the ride is
  /// ended from `onDispose`, where reading another provider is not allowed.
  late NotificationUpdater _notifications;
  late RideLiveActivity _liveActivity;

  /// The text the notification is showing, `null` while no ride runs.
  String? _text;

  /// When that text went out, for the throttle.
  DateTime? _textAt;

  /// The data the live activity is showing, `null` while no card is up.
  Map<String, Object?>? _activity;

  /// When that data went out.
  DateTime? _activityAt;

  @override
  void build() {
    _notifications = ref.read(notificationUpdaterProvider);
    _liveActivity = ref.read(rideLiveActivityProvider);
    ref.listen(recordingControllerProvider, (previous, next) => refresh());
    ref.listen(navigationControllerProvider, (previous, next) => refresh());
    ref.listen(unitSystemProvider, (previous, next) => refresh());
    ref.onDispose(_finish);
    refresh();
  }

  /// Works out what the lock screen should say right now and writes it, as far
  /// as the throttles allow.
  ///
  /// Public so a test can drive it without a recorder; the app only ever gets
  /// here through the listeners above.
  void refresh() {
    final recording = ref.read(recordingControllerProvider);
    final snapshot = recording.snapshot;
    if (!recording.isRecording || snapshot == null) {
      _finish();
      return;
    }
    final progress = ref.read(navigationControllerProvider);
    final l10n = ref.read(navigationLocalizationsProvider);
    final units = ref.read(unitSystemProvider);
    final now = ref.read(rideNotificationClockProvider)();
    _writeNotification(
      rideNotificationText(l10n, units, snapshot, progress),
      now,
    );
    _writeActivity(rideActivityData(l10n, units, snapshot, progress), now);
  }

  void _writeNotification(String text, DateTime now) {
    if (text == _text) return;
    final sentAt = _textAt;
    if (sentAt != null && now.difference(sentAt) < notificationThrottle) return;
    _text = text;
    _textAt = now;
    // The claim goes with every write rather than once at the start: it is
    // a lease, and renewing it is how the service isolate learns that this
    // isolate is still here.
    _notifications.claim(notificationLease);
    unawaited(_notifications.update(text));
  }

  void _writeActivity(Map<String, Object?> data, DateTime now) {
    if (_activity == null) {
      _activity = data;
      _activityAt = now;
      unawaited(_liveActivity.start(data));
      return;
    }
    if (mapEquals(data, _activity)) return;
    final sentAt = _activityAt;
    if (sentAt != null && now.difference(sentAt) < liveActivityThrottle) return;
    _activity = data;
    _activityAt = now;
    unawaited(_liveActivity.update(data));
  }

  /// The ride is over: the card goes, and the service isolate gets its own
  /// notification text back.
  void _finish() {
    if (_text != null) {
      _text = null;
      _textAt = null;
      _notifications.claim(Duration.zero);
    }
    if (_activity != null) {
      _activity = null;
      _activityAt = null;
      unawaited(_liveActivity.end());
    }
  }
}

/// The updater of the running app.
final rideNotificationUpdaterProvider =
    NotifierProvider<RideNotificationUpdater, void>(
      RideNotificationUpdater.new,
    );

/// The second line of the recording notification, e.g.
/// `Turn left in 150 m · 3.2 km · 00:42`.
///
/// Without guidance it is what the service isolate writes on its own: the
/// ride's distance and its running time.
String rideNotificationText(
  AppLocalizations l10n,
  UnitSystem units,
  RecordingSnapshot snapshot,
  NavigationProgress? progress,
) {
  final ride =
      '${formatDistance(l10n, units, snapshot.distanceM)} · '
      '${formatClock(snapshot.elapsed)}';
  final paused = snapshot.status == RecordingStatus.paused ? ' · ⏸' : '';
  final turn = _turnPhrase(l10n, units, progress);
  return turn == null ? '$ride$paused' : '$turn · $ride$paused';
}

/// What the live activity is handed: flat strings and numbers, because the
/// plugin passes them through the App Group's `UserDefaults` and the widget
/// extension reads them one key at a time.
Map<String, Object?> rideActivityData(
  AppLocalizations l10n,
  UnitSystem units,
  RecordingSnapshot snapshot,
  NavigationProgress? progress,
) => <String, Object?>{
  'distance': formatDistance(l10n, units, snapshot.distanceM),
  'elapsed': formatClock(snapshot.elapsed),
  'speed': formatSpeed(l10n, units, snapshot.speedMps),
  'turnIcon': _turnIcon(progress),
  'turnLabel': _turnLabel(l10n, progress) ?? '',
  'turnDistance': _turnDistance(l10n, units, progress) ?? '',
  'paused': snapshot.status == RecordingStatus.paused ? 1 : 0,
};

/// The lead of the notification line: the next turn with the distance to it,
/// or what is wrong instead, or nothing at all when no route is being guided.
String? _turnPhrase(
  AppLocalizations l10n,
  UnitSystem units,
  NavigationProgress? progress,
) {
  final label = _turnLabel(l10n, progress);
  if (label == null) return null;
  final distance = _turnDistance(l10n, units, progress);
  return distance == null ? label : l10n.navTurnIn(label, distance);
}

/// What the rider is being told: the trouble first — off route beats a turn
/// they can no longer take — then the end of the route, then the next turn.
String? _turnLabel(AppLocalizations l10n, NavigationProgress? progress) {
  if (progress == null) return null;
  final guidance = progress.guidance;
  // Off the route with a way back to give, the way back is the news.
  if (guidance != null) return backToRouteLabel(guidance.direction, l10n);
  if (progress.offRoute) return l10n.navOffRoute;
  if (progress.arrived) return l10n.navArrived;
  final next = progress.next;
  return next == null ? null : turnLabel(next, l10n);
}

/// The distance to that turn, or `null` when there is no turn to measure to.
String? _turnDistance(
  AppLocalizations l10n,
  UnitSystem units,
  NavigationProgress? progress,
) {
  if (progress == null) return null;
  final guidance = progress.guidance;
  if (guidance != null) return distanceLabel(guidance.distanceM, l10n, units);
  if (progress.offRoute || progress.arrived) return null;
  final next = progress.next;
  if (next == null) return null;
  return distanceLabel(progress.distanceToNextM, l10n, units);
}

String _turnIcon(NavigationProgress? progress) {
  if (progress == null) return '';
  if (progress.offRoute || progress.guidance != null) return offRouteSymbol;
  if (progress.arrived) return turnSymbol(TurnKind.end);
  final next = progress.next;
  return next == null ? '' : turnSymbol(next.kind);
}
