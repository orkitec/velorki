/// How good a text-to-speech voice sounds, as the platform grades it.
///
/// Listed worst to best, so a higher index is a better voice.
enum VoiceQuality {
  /// The platform said nothing useful about the voice.
  unknown,

  /// A thin, robotic voice; Android's "low" and "very low".
  low,

  /// The plain voice a phone ships with: Android "normal", iOS "default".
  normal,

  /// A better voice, usually downloaded: iOS "enhanced", Android "high".
  enhanced,

  /// The best voice on offer: iOS "premium", Android "very high".
  premium,
}

/// Who the voice sounds like, as far as the platform will say.
enum VoiceGender {
  /// The platform did not say, and the catalogue has never heard of it.
  unknown,

  /// A female voice.
  female,

  /// A male voice.
  male,
}

/// One voice the phone can say the turns in.
///
/// Built from what the `speak` package reports (`voiceOptionFrom` in
/// `turn_speaker.dart`). iOS gives a name ("Samantha"), an identifier, a
/// grade (compact, enhanced or premium) and a gender. Android gives a name
/// that is a machine identifier (`en-us-x-iog-local`), a grade and whether
/// the voice is synthesised online, and no gender.
///
/// [displayName] is what the rider reads. It starts out as [name] and is
/// replaced by the catalogue or by the numbered fallback; see
/// `describeVoices`.
class VoiceOption {
  /// Creates a voice. [displayName] defaults to [name].
  const VoiceOption({
    required this.id,
    required this.name,
    required this.localeTag,
    String? displayName,
    this.gender = VoiceGender.unknown,
    this.quality = VoiceQuality.unknown,
    this.needsNetwork = false,
  }) : displayName = displayName ?? name;

  /// What the choice is stored and looked up by. The iOS identifier, or
  /// name and locale together on Android, where there is no identifier.
  final String id;

  /// The name the platform reports: "Samantha" on iOS, `en-us-x-iog-local`
  /// on Android.
  final String name;

  /// The name the rider reads in the list.
  final String displayName;

  /// The BCP-47 tag the voice speaks, e.g. `en-GB`.
  final String localeTag;

  /// Who the voice sounds like.
  final VoiceGender gender;

  /// How good the voice is.
  final VoiceQuality quality;

  /// Whether the voice is synthesised online. Without a signal such a voice
  /// says nothing, or says it late.
  final bool needsNetwork;

  /// The identifier the engine itself uses: `en-us-x-iog-local` on Android,
  /// `com.apple.voice.compact.en-US.Samantha` on iOS. Shown under the name
  /// so a rider can tell two voices with the same name apart.
  String get rawIdentifier => id == '$name|$localeTag' ? name : id;

  /// The language part of [localeTag], lower-case: `en` for `en-GB`.
  String get language => localeTag.split(RegExp('[-_]')).first.toLowerCase();

  /// A copy with the named fields replaced.
  VoiceOption copyWith({
    String? displayName,
    VoiceGender? gender,
    VoiceQuality? quality,
  }) => VoiceOption(
    id: id,
    name: name,
    localeTag: localeTag,
    displayName: displayName ?? this.displayName,
    gender: gender ?? this.gender,
    quality: quality ?? this.quality,
    needsNetwork: needsNetwork,
  );

  /// Best first: premium over enhanced over normal over low over unknown,
  /// then by the name the rider reads.
  static int compare(VoiceOption a, VoiceOption b) {
    final quality = b.quality.index.compareTo(a.quality.index);
    if (quality != 0) return quality;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceOption &&
          other.id == id &&
          other.name == name &&
          other.displayName == displayName &&
          other.localeTag == localeTag &&
          other.gender == gender &&
          other.quality == quality &&
          other.needsNetwork == needsNetwork;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    displayName,
    localeTag,
    gender,
    quality,
    needsNetwork,
  );

  @override
  String toString() =>
      'VoiceOption($displayName, $name, $localeTag, ${quality.name}, '
      '${gender.name}${needsNetwork ? ', online' : ''})';
}
