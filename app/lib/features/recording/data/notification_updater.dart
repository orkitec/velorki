import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/recording_snapshot.dart';
import 'recording_task_handler.dart';

/// The two foreground-service calls the ride notification needs.
///
/// Behind an interface for the same reason as [ForegroundServiceHost]: both
/// are plugin statics that reach for a platform channel, which a unit test
/// does not have.
abstract interface class NotificationUpdater {
  /// Replaces the second line of the ongoing recording notification.
  Future<void> update(String text);

  /// Tells the service isolate that the main isolate writes the text for the
  /// next [lease], so it stops writing its own. [Duration.zero] hands the
  /// text straight back.
  void claim(Duration lease);
}

/// A [NotificationUpdater] that goes nowhere: iOS, the desktop builds, and
/// every test that has not said otherwise.
class SilentNotificationUpdater implements NotificationUpdater {
  /// Creates the no-op.
  const SilentNotificationUpdater();

  @override
  Future<void> update(String text) async {}

  @override
  void claim(Duration lease) {}
}

/// The real updater, over the `FlutterForegroundTask` statics.
class ForegroundTaskNotificationUpdater implements NotificationUpdater {
  /// Creates the updater.
  const ForegroundTaskNotificationUpdater();

  @override
  Future<void> update(String text) async {
    // `updateService` answers with a failure rather than throwing when no
    // service is running, which is exactly what happens in the second between
    // the last snapshot and the end of a ride. Nothing to do about it.
    await FlutterForegroundTask.updateService(notificationText: text);
  }

  @override
  void claim(Duration lease) =>
      FlutterForegroundTask.sendDataToTask(<String, Object?>{
        recordingMessageKind: recordingCommandMessage,
        recordingCommandKey: recordingCommandNotificationLease,
        recordingNotificationLeaseKey: lease.inMilliseconds,
      });
}

/// The writer of the recording notification: the foreground service on
/// Android, nothing anywhere else.
final notificationUpdaterProvider = Provider<NotificationUpdater>(
  (ref) => defaultTargetPlatform == TargetPlatform.android
      ? const ForegroundTaskNotificationUpdater()
      : const SilentNotificationUpdater(),
);
