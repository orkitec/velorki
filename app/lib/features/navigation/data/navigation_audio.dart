import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The two things a guided ride needs from the iPhone's audio session that
/// the text-to-speech plugin does not offer.
///
/// Both are no-ops off iOS: Android's guidance goes through the engine's own
/// audio attributes (see `FlutterTtsSpeaker`), and neither the session nor
/// the lead-in exists there.
///
/// The channel is handled in `ios/Runner/AppDelegate.swift`; the method names
/// are mirrored there.
class NavigationAudio {
  /// Creates the helper. [channel] and [platform] are injected by the tests.
  NavigationAudio({MethodChannel? channel, TargetPlatform? platform})
    : _channel = channel ?? const MethodChannel(channelName),
      _platform = platform ?? defaultTargetPlatform;

  /// The channel `AppDelegate` answers on.
  static const String channelName = 'app.velorki/audio';

  /// Plays `assets/audio/silence.wav` and answers when it has finished.
  static const String playLeadInMethod = 'playLeadIn';

  /// Hands the audio session back to whatever was playing before.
  static const String deactivateSessionMethod = 'deactivateSession';

  final MethodChannel _channel;
  final TargetPlatform _platform;

  bool get _isIOS => !kIsWeb && _platform == TargetPlatform.iOS;

  /// Plays the silent lead-in and waits for it to finish, at most [timeout].
  ///
  /// A Bluetooth headset that has been quiet for a while lets its A2DP link
  /// go idle and takes about a second to bring it back; speaking into that
  /// gap is what scrambles a cue or eats its first syllables. The silence is
  /// what wakes the link, so the voice starts into an open stream.
  ///
  /// Nothing here throws: a phone that answers late, or not at all, delays a
  /// cue by [timeout] rather than losing it.
  Future<void> playLeadIn(Duration timeout) async {
    if (!_isIOS) return;
    try {
      await _channel
          .invokeMethod<void>(playLeadInMethod)
          .timeout(timeout, onTimeout: () {});
    } catch (error) {
      debugPrint('Navigation audio: the lead-in did not play ($error)');
    }
  }

  /// Gives the audio session back, once a guided ride is over.
  ///
  /// Held open for the whole ride (see `FlutterTtsSpeaker.beginGuidance`),
  /// it has to be closed by hand, or a podcast the cues interrupted never
  /// starts again.
  Future<void> deactivateSession() async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod<void>(deactivateSessionMethod);
    } catch (error) {
      debugPrint('Navigation audio: the session stayed active ($error)');
    }
  }
}
