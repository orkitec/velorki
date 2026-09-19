import 'dart:async';

import '../data/watch_gateway.dart';

/// A [WatchGateway] that writes down what the phone sent and lets a test play
/// the watch.
///
/// Lives in `lib/` rather than `test/` so the widget tests and the integration
/// tests can both override `watchGatewayProvider` with it — the same reason
/// `FakeHealthGateway` does.
class FakeWatchGateway implements WatchGateway {
  /// Creates a fake. A paired, reachable watch by default, because that is
  /// what every test is about.
  FakeWatchGateway({
    this.supported = true,
    this.paired = true,
    this.reachable = true,
  });

  /// What [isSupported] answers.
  bool supported;

  /// What [isPaired] answers.
  bool paired;

  /// What [isReachable] answers.
  bool reachable;

  /// Every message the phone sent, in order.
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  /// Every application context the phone pushed, in order.
  final List<Map<String, Object?>> contexts = <Map<String, Object?>>[];

  /// How often [launchWorkout] was asked, and what it answers.
  int launches = 0;
  bool launchSucceeds = true;

  @override
  Future<bool> launchWorkout() async {
    launches++;
    return launchSucceeds;
  }

  final StreamController<Map<String, Object?>> _messages =
      StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isPaired() async => paired;

  @override
  Future<bool> isReachable() async => reachable;

  @override
  Future<void> sendMessage(Map<String, Object?> message) async =>
      sent.add(Map<String, Object?>.from(message));

  @override
  Future<void> updateApplicationContext(Map<String, Object?> context) async =>
      contexts.add(Map<String, Object?>.from(context));

  /// Plays the watch: pushes [message] as if it had come off the wrist.
  void receive(Map<String, Object?> message) {
    if (_messages.isClosed) return;
    _messages.add(message);
  }

  /// Closes the message stream. A test that made one calls this in a teardown.
  Future<void> dispose() => _messages.close();
}
