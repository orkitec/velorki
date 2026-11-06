// The phone's own text-to-speech, not the fake: the simulator and the
// emulator have voices, and a cue said through the real speaker has to come
// back as finished, in either treatment of other audio. Skipped where there
// is no engine (the web, desktops).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool hasEngine() => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  for (final otherAudio in InstructionAudio.values) {
    testWidgets('the real speaker has voices and says a cue to the end '
        '(${otherAudio.name})', (tester) async {
      if (!hasEngine()) {
        markTestSkipped('needs the iOS simulator or an Android emulator');
        return;
      }
      final speaker = SpeakTurnSpeaker(otherAudio: otherAudio);
      addTearDown(speaker.dispose);

      final voices = await speaker.voices();
      expect(voices, isNotEmpty, reason: 'no English voice on this device');
      expect(voices.every((v) => v.language == 'en'), isTrue);

      // Resolves when the engine is done; a hang here is the engine never
      // starting, which is how the voice broke once on a phone. A cue the
      // engine dropped would come back at once, so the time it took is the
      // proof it was said: the lead-in alone is a third of a second.
      final watch = Stopwatch()..start();
      await speaker
          .speak('In 100 metres, turn left')
          .timeout(const Duration(seconds: 20));
      expect(watch.elapsed, greaterThan(const Duration(milliseconds: 800)));

      // A second cue in the linger: no lead-in, still said.
      watch.reset();
      await speaker
          .speak('Turn left now', urgent: true)
          .timeout(const Duration(seconds: 20));
      expect(watch.elapsed, greaterThan(const Duration(milliseconds: 300)));
    });
  }

  testWidgets('a chosen voice is used, and an urgent cue cuts in', (
    tester,
  ) async {
    if (!hasEngine()) {
      markTestSkipped('needs the iOS simulator or an Android emulator');
      return;
    }
    final speaker = SpeakTurnSpeaker();
    addTearDown(speaker.dispose);
    final voices = await speaker.voices();
    await speaker.selectVoice(voices.last.id);

    final long = speaker.speak(
      'In five hundred metres, keep left and follow the river path to the '
      'bridge',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final watch = Stopwatch()..start();
    await speaker
        .speak('Turn left now', urgent: true)
        .timeout(const Duration(seconds: 20));
    await long.timeout(const Duration(seconds: 1));
    // The long cue was cut off, not waited for.
    expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
  });
}
