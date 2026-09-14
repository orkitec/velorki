import '../data/turn_speaker.dart';

/// A [TurnSpeaker] that writes down what it was asked to say.
///
/// Lives in `lib/` rather than `test/` so widget tests and the integration
/// tests can both override `turnSpeakerProvider` with it.
class FakeTurnSpeaker implements TurnSpeaker {
  /// Everything [speak] was called with, in order.
  final List<String> spoken = <String>[];

  /// How often [stop] was called.
  int stops = 0;

  /// Whether [dispose] was called.
  bool disposed = false;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
