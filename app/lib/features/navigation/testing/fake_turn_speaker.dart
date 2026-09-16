import '../data/turn_speaker.dart';
import '../domain/voice_option.dart';

/// A [TurnSpeaker] that writes down what it was asked to say.
///
/// Lives in `lib/` rather than `test/` so widget tests and the integration
/// tests can both override `turnSpeakerProvider` with it.
class FakeTurnSpeaker implements TurnSpeaker {
  /// Creates a fake that offers [available].
  FakeTurnSpeaker({this.available = const <VoiceOption>[]});

  /// Everything [speak] was called with, in order.
  final List<String> spoken = <String>[];

  /// How often [stop] was called.
  int stops = 0;

  /// Whether [dispose] was called.
  bool disposed = false;

  /// What [voices] hands out.
  final List<VoiceOption> available;

  /// Every id [selectVoice] was called with, in order.
  final List<String?> selections = <String?>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<List<VoiceOption>> voices() async => available;

  @override
  Future<void> selectVoice(String? id) async => selections.add(id);

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
