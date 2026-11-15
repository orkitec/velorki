---
title: Why we wrote our own text-to-speech package for Flutter
description: Turn-by-turn directions over music and a Bluetooth headset need more than a speak call. What went wrong, and what the speak package does instead.
date: 2026-11-15
author: steffen
category: engineering
image: cover.png
imageAlt: 'Timeline of a podcast during three spoken turn cues. Before, the podcast paused at the first cue and stayed paused for the rest of the ride. With speak, it pauses only for each cue and its short silent lead-in, and plays again in between.'
draft: true
---

Velorki speaks its turn instructions: "In 200 metres, turn left." That sounds like the easy part of a navigation app. It turned out to be the part riders noticed most when it went wrong, and it led to [speak](https://pub.dev/packages/speak), a small text-to-speech package for Flutter that we now publish separately.

## What a spoken direction has to get right

A rider usually has something else playing: music, a podcast, an audiobook, and often through a Bluetooth headset or speaker. A cue has to:

- **Be heard from the first syllable.** "…eft" is not a direction.
- **Come at the right moment, or not at all.** A "turn in 200 metres" that waited behind another cue and plays after the turn is worse than silence.
- **Make room for itself and give it back.** Lower the music while it speaks, pause a podcast so no sentence is lost, and bring both back right after.
- **Step aside for a phone call.**

## Where the plugin we used fell short

Velorki started with `flutter_tts`, the widely used Flutter plugin. It speaks text fine. The trouble was everything around it.

- **Lost first syllables on Bluetooth.** On iOS it gave up the shared audio session after every utterance. A Bluetooth headset then closed its audio link, and the next cue had to reopen it, which swallowed the first syllables or scrambled them.
- **The workaround was worse for podcasts.** We kept the audio session for the whole ride instead and played a second of silence before each cue to wake the link. Cues were complete again, but a podcast paused for the first cue stayed paused for the whole ride.
- **No timing model.** A call that returns when speaking starts doesn't tell you when it ended or whether it was cut off. Velorki had grown its own queue on top, with its own guesses.
- **It was our last CocoaPods dependency.** Everything else in the iOS app had moved to Swift Package Manager. CocoaPods' central repository is going read-only, and this one plugin kept the whole iOS build on it.

## What speak does instead

```dart
final speak = Speak(audio: SpeakAudio.navigation);

await speak('In two hundred metres, turn left.');
await speak('Turn left now.', queue: SpeakQueue.interrupt);
```

- **Every call can be awaited** and says how it ended: completed, interrupted, expired, or blocked (by a phone call).
- **Queue, interrupt, expire.** Cues wait their turn by default, an urgent one cuts in, and a distance announcement can be given a deadline after which it is dropped unsaid.
- **Audio is claimed only while speaking.** The iOS audio session and Android's audio focus are taken right before a cue and released shortly after, so a podcast pauses for a sentence and then carries on.
- **A short silent lead-in on Bluetooth**, so the headset is awake when the first word arrives, and a short linger so two cues in a row don't reopen the link.
- **Calls come first.** If a call is active, a cue ends as blocked instead of talking over it. On iOS that check uses CallKit, which the package loads at run time rather than linking, because apps containing CallKit are not accepted on the App Store in China.

In Velorki the rider chooses what happens to other audio during an instruction: pause spoken audio and lower music (the default), or only lower the volume.

## No native code to write

speak calls each platform's own speech engine directly from Dart. On iOS and macOS that is AVFoundation through FFI; on Android it is `TextToSpeech` through JNI, plus one small Java class for the progress callback; on the web it is the Web Speech API. The glue is generated and compiled by Flutter's build hooks, so an app adds the package and nothing else: no Podfile, no Swift package, no Kotlin.

## Testing something you have to hear

Speech engines on CI machines have no speakers, and they behave accordingly: an Android emulator can report no voices for the first seconds after start, and engines sometimes stall on virtual audio devices. The package's CI runs on iOS, macOS, Android and the web, records what the engine reported, and retries only the stalls the environment causes, never a real failure.

The real test was a ride. Guidance runs on speak since Velorki 1.2.3, and on the iPhone the cues came through whole and on time.

## Use it

speak is BSD-licensed and on [pub.dev](https://pub.dev/packages/speak), with the source on [GitHub](https://github.com/orkitec/speak). It is made for short prompts over other audio: directions, workout cues, timers. Windows and Linux are not supported yet. If you need one of them and can test it, open an issue.
