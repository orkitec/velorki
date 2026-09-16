import 'voice_catalogue.dart';
import 'voice_option.dart';

/// The words the voice list needs, handed in from the translations so this
/// stays free of Flutter.
///
/// Every label a rider reads is built here from translated pieces: nothing
/// in the bundled catalogue is shown, because it is English-only.
class VoiceNaming {
  /// Creates the naming with the translated words.
  const VoiceNaming({
    required this.female,
    required this.male,
    required this.label,
    required this.labelGeneric,
    required this.enhanced,
    required this.premium,
    required this.regionName,
    required this.languageName,
  });

  /// "Female".
  final String female;

  /// "Male".
  final String male;

  /// "Female voice 2 (United States)".
  final String Function(String gender, int number, String region) label;

  /// "Voice 2 (United States)", for a voice whose gender nobody will say.
  final String Function(int number, String region) labelGeneric;

  /// "Enhanced".
  final String enhanced;

  /// "Premium".
  final String premium;

  /// What to call the region of a locale tag: "United States" for `en-US`.
  final String Function(String localeTag) regionName;

  /// What to call the language of a locale tag: "English" for `en-US`.
  final String Function(String localeTag) languageName;

  /// The name of the [number]th [gender] voice for [localeTag].
  String voiceLabel(VoiceGender gender, int number, String localeTag) {
    final region = regionName(localeTag);
    return switch (gender) {
      VoiceGender.female => label(female, number, region),
      VoiceGender.male => label(male, number, region),
      VoiceGender.unknown => labelGeneric(number, region),
    };
  }

  /// The badge for [quality], or `null` for an everyday voice.
  String? badge(VoiceQuality quality) => switch (quality) {
    VoiceQuality.premium => premium,
    VoiceQuality.enhanced => enhanced,
    _ => null,
  };
}

/// Gives every voice a name a rider can read, and sorts them best first.
///
/// On Android the name is built from the translations — "Female voice 1
/// (United States)" — numbered per language, region and gender in the order
/// the engine listed them, because `en-us-x-iog-local` means nothing to
/// anybody. The catalogue is asked for the gender and the quality the engine
/// keeps to itself, never for a name: its labels are English only.
///
/// [apple] is set on iOS, where the plugin reports a real name — a proper
/// noun, the same in every language — and the quality badge belongs behind
/// it.
///
/// [preferredLocaleTag] is the rider's own locale: its region's voices come
/// first, since "English" on a US phone means US English before Nigerian.
List<VoiceOption> describeVoices(
  List<VoiceOption> voices, {
  required VoiceCatalogue catalogue,
  required VoiceNaming naming,
  bool apple = false,
  String? preferredLocaleTag,
}) {
  // Google lists every region twice: a `<lang>-<REGION>-language` alias and
  // the voice it stands for, `<lang>-<region>-x-<id>-local`. The alias is
  // the same voice under a duller name, so it is left out whenever the
  // real one is there.
  final regionsWithVoices = <String>{
    for (final voice in voices)
      if (!isRegionAlias(voice)) voice.localeTag.toLowerCase(),
  };
  final counters = <String, int>{};
  final described = <VoiceOption>[];
  for (final voice in voices) {
    if (isRegionAlias(voice) &&
        regionsWithVoices.contains(voice.localeTag.toLowerCase())) {
      continue;
    }
    final entry = catalogue.lookup(voice);
    final gender = voice.gender != VoiceGender.unknown
        ? voice.gender
        : entry?.gender ?? VoiceGender.unknown;
    final quality = voice.quality != VoiceQuality.unknown
        ? voice.quality
        : entry?.quality ?? VoiceQuality.unknown;

    final String label;
    if (apple) {
      final badge = naming.badge(quality);
      label = badge == null ? voice.name : '${voice.name} ($badge)';
    } else {
      final key =
          '${voice.localeTag}|${gender.name}|${voice.needsNetwork ? 'online' : 'local'}';
      // Online voices count on their own: the picker hides them by default
      // and a hidden voice must not leave a gap in the numbering.
      final number = (counters[key] ?? 0) + 1;
      counters[key] = number;
      label = naming.voiceLabel(gender, number, voice.localeTag);
    }

    described.add(
      voice.copyWith(displayName: label, gender: gender, quality: quality),
    );
  }
  final preferred = preferredLocaleTag?.toLowerCase().replaceAll('_', '-');
  int compare(VoiceOption a, VoiceOption b) {
    if (preferred != null) {
      final aHome = a.localeTag.toLowerCase().replaceAll('_', '-') == preferred;
      final bHome = b.localeTag.toLowerCase().replaceAll('_', '-') == preferred;
      if (aHome != bHome) return aHome ? -1 : 1;
    }
    return VoiceOption.compare(a, b);
  }

  return described..sort(compare);
}

/// Whether [voice] is one of Google's per-region default aliases: the same
/// voice the engine also lists under its own name, e.g. `en-US-language`
/// beside `en-us-x-iog-local`.
bool isRegionAlias(VoiceOption voice) =>
    voice.name.toLowerCase().endsWith('-language');
