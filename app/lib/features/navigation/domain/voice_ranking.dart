import 'voice_naming.dart';
import 'voice_option.dart';

/// The best voice on the phone for [localeTag], or `null` when none of them
/// beats what the engine would pick on its own.
///
/// This is what "System default" resolves to. Phones ship the thin compact
/// voice and leave the good ones as a free download — Apple under Settings ›
/// Accessibility › Spoken Content › Voices, Google with the engine's voice
/// data — and the engine's own default stays whatever was installed first.
/// A rider who downloads a better voice should hear it without going back
/// into the picker.
///
/// The order, best first:
///
/// 1. the grade the platform reports: premium over enhanced over the
///    everyday voice. A voice the platform grades as nothing at all counts
///    as an everyday one — Android says nothing about most of its voices,
///    and a voice with no grade is no reason to prefer it;
/// 2. the exact locale tag over another region of the same language, so
///    `en-GB` cues get the British voice when the grades are equal;
/// 3. the voice's own name over Google's per-region alias for it, which is
///    the same voice listed twice;
/// 4. the platform's own name, so the answer never depends on the order the
///    engine happened to list its voices in.
///
/// Voices synthesised online are left out altogether rather than ranked
/// last: a ride has no guaranteed signal, and such a voice says the turn
/// late or not at all. Voices for another language are left out too.
///
/// `null` means "leave it to the platform": either there is nothing
/// installed for the language, or the best of it is the everyday voice,
/// which is what the engine would have used anyway.
VoiceOption? bestVoiceFor(List<VoiceOption> voices, String localeTag) {
  final language = _languageOf(localeTag);
  final candidates = voices
      .where((voice) => !voice.needsNetwork && voice.language == language)
      .toList();
  if (candidates.isEmpty) return null;
  final wanted = _normalise(localeTag);
  candidates.sort((a, b) {
    final quality = _rank(b.quality).compareTo(_rank(a.quality));
    if (quality != 0) return quality;
    final aExact = _normalise(a.localeTag) == wanted;
    final bExact = _normalise(b.localeTag) == wanted;
    if (aExact != bExact) return aExact ? -1 : 1;
    final aAlias = isRegionAlias(a);
    final bAlias = isRegionAlias(b);
    if (aAlias != bAlias) return aAlias ? 1 : -1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  final best = candidates.first;
  // Only a voice the rider went and downloaded is worth overriding the
  // engine's choice with.
  return _rank(best.quality) >= _rank(VoiceQuality.enhanced) ? best : null;
}

/// How good [quality] is for the purpose of choosing a default. A grade the
/// platform did not give counts as the everyday voice.
int _rank(VoiceQuality quality) => switch (quality) {
  VoiceQuality.premium => 3,
  VoiceQuality.enhanced => 2,
  VoiceQuality.normal || VoiceQuality.unknown => 1,
  VoiceQuality.low => 0,
};

String _languageOf(String localeTag) =>
    localeTag.split(RegExp('[-_]')).first.toLowerCase();

String _normalise(String localeTag) =>
    localeTag.toLowerCase().replaceAll('_', '-');
