/// What the card of a place shows from its OpenStreetMap tags.
library;

/// Whether a place can be reached in a wheelchair (`wheelchair`).
enum WheelchairAccess {
  /// `yes` (or `designated`).
  yes,

  /// `limited`.
  limited,

  /// `no`.
  no,
}

/// The tags of an OpenStreetMap element the place card has a row for.
class OsmPlaceDetails {
  /// Creates details; every field is optional.
  const OsmPlaceDetails({
    this.openingHours,
    this.website,
    this.phone,
    this.cuisines = const <String>[],
    this.wheelchair,
    this.outdoorSeating = false,
    this.wikipedia,
    this.wikipediaTitle,
  });

  /// Reads the rows out of [tags].
  factory OsmPlaceDetails.fromTags(Map<String, String> tags) {
    String? tag(String key) {
      final value = tags[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final wiki = _wikipedia(tag('wikipedia'));
    return OsmPlaceDetails(
      openingHours: tag('opening_hours'),
      website: _website(tag('website') ?? tag('contact:website')),
      phone: _first(tag('phone') ?? tag('contact:phone')),
      cuisines: <String>[
        for (final c in (tag('cuisine') ?? '').split(';'))
          if (c.trim().isNotEmpty) c.trim().replaceAll('_', ' '),
      ],
      wheelchair: switch (tag('wheelchair')) {
        'yes' || 'designated' => WheelchairAccess.yes,
        'limited' => WheelchairAccess.limited,
        'no' => WheelchairAccess.no,
        _ => null,
      },
      outdoorSeating: tag('outdoor_seating') == 'yes',
      wikipedia: wiki?.url,
      wikipediaTitle: wiki?.title,
    );
  }

  /// The tags [OsmPlaceDetails.fromTags] reads; the others need not be
  /// kept.
  static const Set<String> tagKeys = <String>{
    'opening_hours',
    'website',
    'contact:website',
    'phone',
    'contact:phone',
    'cuisine',
    'wheelchair',
    'outdoor_seating',
    'wikipedia',
  };

  /// Nothing to show.
  static const OsmPlaceDetails empty = OsmPlaceDetails();

  /// The raw `opening_hours` value.
  final String? openingHours;

  /// The place's web page, http or https only.
  final Uri? website;

  /// The first phone number given.
  final String? phone;

  /// The cuisines, readable (`vietnamese`, `ice cream`).
  final List<String> cuisines;

  /// Whether it can be reached in a wheelchair, when tagged.
  final WheelchairAccess? wheelchair;

  /// Whether it has seats outside.
  final bool outdoorSeating;

  /// The Wikipedia article about it.
  final Uri? wikipedia;

  /// The title of [wikipedia], as written in the tag.
  final String? wikipediaTitle;

  /// [phone] as a link to dial.
  Uri? get phoneUri {
    final digits = phone?.replaceAll(RegExp(r'[^\d+]'), '');
    return digits == null || digits.isEmpty
        ? null
        : Uri(scheme: 'tel', path: digits);
  }

  /// Whether there is nothing to show.
  bool get isEmpty =>
      openingHours == null &&
      website == null &&
      phone == null &&
      cuisines.isEmpty &&
      wheelchair == null &&
      !outdoorSeating &&
      wikipedia == null;

  static String? _first(String? value) {
    final first = value?.split(';').first.trim();
    return first == null || first.isEmpty ? null : first;
  }

  static Uri? _website(String? value) {
    final first = _first(value);
    if (first == null) return null;
    final uri = Uri.tryParse(first.contains('://') ? first : 'https://$first');
    if (uri == null || uri.host.isEmpty) return null;
    return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
  }

  /// `de:Kölner Dom` → the article on de.wikipedia.org.
  static ({Uri url, String title})? _wikipedia(String? value) {
    final m = RegExp(r'^([a-z][a-z\-]{1,11}):(.+)$').firstMatch(value ?? '');
    if (m == null) return null;
    final title = m[2]!.trim();
    if (title.isEmpty) return null;
    return (
      url: Uri(
        scheme: 'https',
        host: '${m[1]}.wikipedia.org',
        pathSegments: <String>['wiki', title.replaceAll(' ', '_')],
      ),
      title: title,
    );
  }
}
