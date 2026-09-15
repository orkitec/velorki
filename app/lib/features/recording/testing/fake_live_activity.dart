import '../data/live_activity.dart';

/// A [RideLiveActivity] that records what the lock screen was asked to show.
///
/// Lives in `lib/` rather than `test/` so the widget tests and the
/// integration tests can both override `rideLiveActivityProvider` with it.
class FakeRideLiveActivity implements RideLiveActivity {
  /// Every call, in order: `start`, `update`, `end`.
  final List<String> calls = <String>[];

  /// The data of every start and every update, in order.
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  /// What the card is showing, or `null` when none was ever put up.
  Map<String, Object?>? get last => payloads.isEmpty ? null : payloads.last;

  /// Whether a card is up right now.
  bool get isRunning =>
      calls.isNotEmpty && calls.contains('start') && calls.last != 'end';

  @override
  Future<void> start(Map<String, Object?> data) async {
    calls.add('start');
    payloads.add(data);
  }

  @override
  Future<void> update(Map<String, Object?> data) async {
    calls.add('update');
    payloads.add(data);
  }

  @override
  Future<void> end() async => calls.add('end');
}
