// The phone's own text-to-speech, not the fake: a cue said through the real
// speaker has to come back as finished, in either treatment of other audio.
//
// A phone can also have no engine at all, which an AOSP emulator and a
// Google-free Android (a plain AOSP build, LineageOS) are, and that is a
// state this file asserts rather than skips: the speaker must say so, say
// nothing, and above all not hang, because a ride navigates on in silence.
// Skipped only where there is no platform speech at all (the web, desktops).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool speechPlatform() => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  for (final otherAudio in InstructionAudio.values) {
    testWidgets('the real speaker has voices and says a cue to the end '
        '(${otherAudio.name})', (tester) async {
      if (!speechPlatform()) {
        markTestSkipped('needs the iOS simulator or an Android emulator');
        return;
      }
      final speaker = SpeakTurnSpeaker(otherAudio: otherAudio);
      addTearDown(speaker.dispose);

      // An AOSP image has no text-to-speech engine installed at all, which
      // is the ordinary state of a Google-free Android. Nothing here may
      // hang or throw there; the voice simply has nothing to speak with.
      if (!await speaker.hasEngine()) {
        expect(await speaker.voices(), isEmpty);
        expect(await speaker.defaultVoice(), isNull);
        // The cue is dropped, and quickly: a ride must not wait on an
        // engine that is not there.
        final quiet = Stopwatch()..start();
        await speaker
            .speak('In 100 metres, turn left')
            .timeout(const Duration(seconds: 20));
        await speaker
            .speak('Turn left now', urgent: true)
            .timeout(const Duration(seconds: 20));
        expect(quiet.elapsed, lessThan(const Duration(seconds: 10)));
        // Every other call navigation makes on it goes through too: a ride
        // on such a phone guides in silence rather than falling over.
        await speaker.beginGuidance();
        await speaker.selectVoice(null);
        await speaker.speak('Turn right now', urgent: true);
        await speaker.endGuidance();
        await speaker.stop();
        return;
      }

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
    if (!speechPlatform()) {
      markTestSkipped('needs the iOS simulator or an Android emulator');
      return;
    }
    final speaker = SpeakTurnSpeaker();
    addTearDown(speaker.dispose);
    if (!await speaker.hasEngine()) {
      // Nothing to choose between; the engineless case is asserted above.
      expect(await speaker.voices(), isEmpty);
      return;
    }
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

  testWidgets('a phone with no engine is told so where the voice is chosen', (
    tester,
  ) async {
    if (!speechPlatform()) {
      markTestSkipped('needs the iOS simulator or an Android emulator');
      return;
    }
    final container = await pumpApp(tester, realMap: false);
    final engine = await container.read(speechEngineInstalledProvider.future);
    // Below MaterialApp: its own element sits above the localizations.
    final l10n = AppLocalizations.of(
      tester.element(find.byType(PlannerScreen)),
    );

    container.read(routerProvider).go(settingsRoute);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text(l10n.settingsNavigation));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text(l10n.settingsVoicePick));
    await pumpFor(tester, const Duration(seconds: 2));

    if (engine) {
      // A phone with an engine shows voices, not either of the two notes.
      expect(find.text(l10n.settingsVoiceNoEngine), findsNothing);
    } else {
      // The one line that helps on a Google-free Android: install an engine.
      expect(find.text(l10n.settingsVoiceNoEngine), findsOneWidget);
    }
    await unmountApp(tester);
  });
}
