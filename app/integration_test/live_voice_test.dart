// The phone's own text-to-speech, not the fake: the simulator has voices,
// and a cue said through the real speaker has to come back as finished.
// Skipped off iOS.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the real speaker has voices and says a cue to the end', (
    tester,
  ) async {
    if (!Platform.isIOS) {
      markTestSkipped('needs the iOS simulator');
      return;
    }
    final speaker = FlutterTtsSpeaker(localeTag: 'en-US');
    addTearDown(speaker.dispose);

    final voices = await speaker.voices();
    expect(voices, isNotEmpty, reason: 'no English voice on the simulator');
    expect(voices.every((v) => v.language == 'en'), isTrue);

    // awaitSpeakCompletion is on, so this resolves when the engine is done;
    // a hang here is the engine never starting, which is how the voice broke
    // once on a phone.
    await speaker
        .speak('In 100 metres, turn left')
        .timeout(const Duration(seconds: 20));
  });
}
