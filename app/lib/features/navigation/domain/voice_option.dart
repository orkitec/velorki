/// How good a text-to-speech voice sounds, as the platform grades it.
enum VoiceQuality {
  /// The plain voice every phone ships with.
  standard,

  /// A better voice, usually downloaded: iOS "enhanced", Android "high".
  enhanced,

  /// The best voice on offer: iOS "premium", Android "very high".
  premium,
}

/// One voice the phone can say the turns in.
///
/// Built from what the text-to-speech plugin reports, which differs per
/// platform: iOS gives an identifier, a quality and a gender; Android gives a
/// quality, a latency and whether the voice is synthesised online.
class VoiceOption {
  /// Creates a voice.
  const VoiceOption({
    required this.id,
    required this.name,
    required this.localeTag,
    this.quality = VoiceQuality.standard,
    this.needsNetwork = false,
  });

  /// The voice as the plugin lists it, or `null` when the entry is unusable.
  static VoiceOption? fromPlatform(Map<Object?, Object?> raw) {
    final name = raw['name'];
    final locale = raw['locale'];
    if (name is! String ||
        name.isEmpty ||
        locale is! String ||
        locale.isEmpty) {
      return null;
    }
    final identifier = raw['identifier'];
    final features = raw['features'];
    return VoiceOption(
      id: identifier is String && identifier.isNotEmpty
          ? identifier
          : '$name|$locale',
      name: name,
      localeTag: locale,
      quality: switch ((raw['quality'] as String? ?? '').toLowerCase()) {
        'premium' || 'very high' => VoiceQuality.premium,
        'enhanced' || 'high' => VoiceQuality.enhanced,
        _ => VoiceQuality.standard,
      },
      needsNetwork:
          raw['network_required'] == '1' ||
          (features is String && features.contains('networkTts')),
    );
  }

  /// What the choice is stored and looked up by. The iOS identifier, or
  /// name and locale together on Android, where there is no identifier.
  final String id;

  /// The name the platform shows for the voice, e.g. "Samantha".
  final String name;

  /// The BCP-47 tag the voice speaks, e.g. `en-GB`.
  final String localeTag;

  /// How good the voice is.
  final VoiceQuality quality;

  /// Whether the voice is synthesised online. Without a signal such a voice
  /// says nothing, or says it late.
  final bool needsNetwork;

  /// The language part of [localeTag], lower-case: `en` for `en-GB`.
  String get language => localeTag.split(RegExp('[-_]')).first.toLowerCase();

  /// What the plugin's `setVoice` wants.
  Map<String, String> get platformVoice => <String, String>{
    'name': name,
    'locale': localeTag,
    if (id != '$name|$localeTag') 'identifier': id,
  };

  /// Best first: premium over enhanced over standard, on the phone before
  /// online, then by name.
  static int compare(VoiceOption a, VoiceOption b) {
    final quality = b.quality.index.compareTo(a.quality.index);
    if (quality != 0) return quality;
    if (a.needsNetwork != b.needsNetwork) return a.needsNetwork ? 1 : -1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceOption &&
          other.id == id &&
          other.name == name &&
          other.localeTag == localeTag &&
          other.quality == quality &&
          other.needsNetwork == needsNetwork;

  @override
  int get hashCode => Object.hash(id, name, localeTag, quality, needsNetwork);

  @override
  String toString() =>
      'VoiceOption($name, $localeTag, ${quality.name}'
      '${needsNetwork ? ', online' : ''})';
}
