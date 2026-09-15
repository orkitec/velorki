import '../data/notification_updater.dart';

/// A [NotificationUpdater] that writes the ongoing notification down instead
/// of asking the foreground service for it.
///
/// Lives in `lib/` rather than `test/` so the widget tests and the
/// integration tests can both override `notificationUpdaterProvider` with it.
class FakeNotificationUpdater implements NotificationUpdater {
  /// Every text the notification was asked to show, in order.
  final List<String> texts = <String>[];

  /// Every lease handed to the service isolate, in order; `Duration.zero`
  /// means the text was given back.
  final List<Duration> leases = <Duration>[];

  /// The text the notification is showing, or `null` when nothing was written.
  String? get lastText => texts.isEmpty ? null : texts.last;

  @override
  Future<void> update(String text) async => texts.add(text);

  @override
  void claim(Duration lease) => leases.add(lease);
}
