import 'voice_option.dart';

/// What the catalogue knows about one voice.
class VoiceCatalogueEntry {
  /// Creates an entry.
  const VoiceCatalogueEntry({
    required this.label,
    this.gender = VoiceGender.unknown,
    this.quality = VoiceQuality.unknown,
    this.language,
  });

  /// Reads one entry of the asset; `null` when it has no label.
  static VoiceCatalogueEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    if (label is! String || label.isEmpty) return null;
    return VoiceCatalogueEntry(
      label: label,
      gender: switch (raw['gender']) {
        'female' => VoiceGender.female,
        'male' => VoiceGender.male,
        _ => VoiceGender.unknown,
      },
      quality: switch (raw['quality']) {
        'premium' => VoiceQuality.premium,
        'enhanced' => VoiceQuality.enhanced,
        'normal' => VoiceQuality.normal,
        'low' => VoiceQuality.low,
        _ => VoiceQuality.unknown,
      },
      language: raw['language'] is String ? raw['language'] as String : null,
    );
  }

  /// Upstream's own name for the voice, e.g. "Female voice 3 (US)". English
  /// only, so it is never shown: it is here to make an entry recognisable.
  final String label;

  /// Who the voice sounds like.
  final VoiceGender gender;

  /// The best grade the voice can be installed in.
  final VoiceQuality quality;

  /// The BCP-47 tag the catalogue lists the voice under, e.g. `en-US`.
  final String? language;
}

/// Friendly names for the voices the phones ship with.
///
/// The engines name their voices for machines and keep the rest to
/// themselves: Android hands out `en-us-x-iog-local` with no word on who it
/// sounds like. `assets/voices/catalogue.json` (see the README next to it)
/// fills in the gender and the quality; the name a rider reads is built from
/// the translations, never from here.
class VoiceCatalogue {
  /// Creates a catalogue over [entries], keyed by lower-case identifier.
  const VoiceCatalogue(this.entries);

  /// A catalogue that knows nothing; used when the asset cannot be read.
  const VoiceCatalogue.empty() : entries = const {};

  /// Reads the asset.
  factory VoiceCatalogue.fromJson(Map<String, Object?> json) {
    final entries = <String, VoiceCatalogueEntry>{};
    for (final pair in json.entries) {
      final entry = VoiceCatalogueEntry.fromJson(pair.value);
      if (entry != null) entries[pair.key.toLowerCase()] = entry;
    }
    return VoiceCatalogue(entries);
  }

  /// The voices, by lower-case identifier.
  final Map<String, VoiceCatalogueEntry> entries;

  /// How many voices the catalogue knows.
  int get length => entries.length;

  /// What the catalogue knows about [voice], or `null` when it has never
  /// heard of it.
  VoiceCatalogueEntry? lookup(VoiceOption voice) {
    for (final key in candidateKeys(voice)) {
      final entry = entries[key];
      if (entry != null) return entry;
    }
    return null;
  }

  /// The keys [voice] could be listed under, best guess first.
  ///
  /// Android reports the bare identifier (`en-us-x-iog-local`), which is the
  /// key itself. iOS reports the Apple name ("Samantha") plus an identifier
  /// such as `com.apple.voice.enhanced.en-US.Samantha` or
  /// `com.apple.ttsbundle.Samantha-compact`; the catalogue lists those under
  /// the name, so the tail of the identifier is tried as well for the voices
  /// whose reported name is localised.
  static List<String> candidateKeys(VoiceOption voice) {
    final keys = <String>[
      voice.name.toLowerCase(),
      voice.id.toLowerCase(),
      // "Android Speech Recognition and Synthesis from Google en-us-x-iog-local"
      if (voice.name.contains(' ')) voice.name.split(' ').last.toLowerCase(),
    ];
    final id = voice.id.toLowerCase();
    if (id.startsWith('com.apple.')) {
      var tail = id.split('.').last;
      // `Samantha-compact`, `siri_female_en-GB_compact`.
      for (final suffix in const ['-compact', '-premium', '-enhanced']) {
        if (tail.endsWith(suffix)) {
          tail = tail.substring(0, tail.length - suffix.length);
        }
      }
      if (tail.isNotEmpty) keys.add(tail);
    }
    return keys.where((key) => key.isNotEmpty).toList();
  }
}
