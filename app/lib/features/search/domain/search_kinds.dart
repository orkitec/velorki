/// The `pois.kind` values the app knows, and the words that ask for the
/// nearest one of them.
library;

import 'fuzzy.dart';

/// Every POI kind this build recognises, in the order the kind search offers
/// them when several match what was typed.
const List<String> searchPoiKinds = <String>[
  'drinking_water',
  'toilets',
  'bicycle_repair_station',
  'bicycle_shop',
  'bicycle_tube_vending',
  'bicycle_rental',
  'bicycle_parking',
  'charging_station',
  'shelter',
  'cafe',
  'restaurant',
  'fast_food',
  'ice_cream',
  'fuel',
  'compressed_air',
  'bakery',
  'supermarket',
  'pharmacy',
  'picnic_site',
  'camp_site',
  'hotel',
  'hostel',
  'alpine_hut',
  'station',
  'bus_stop',
  'tram_stop',
  'airport',
  'ferry_terminal',
  'hospital',
  'university',
  'stadium',
  'mall',
  'viewpoint',
  'peak',
  'mountain_pass',
  'park',
  'water',
  'beach',
  'nature_reserve',
  'attraction',
  'museum',
  'historic',
  'place_of_worship',
  'tower',
  'lighthouse',
  'building',
];

/// The English words that name a kind, whatever the app is translated into.
///
/// A rider on a German phone still types "bakery" now and then, and an English
/// speaker on a borrowed phone types nothing else, so these are always
/// searched next to the localised labels. Deliberately plain: a word that a
/// place could plausibly be called ("building", "water") is left out or made
/// specific, because a kind search pushes real name matches down the list.
const Map<String, List<String>> englishKindKeywords = <String, List<String>>{
  'drinking_water': <String>[
    'drinking water',
    'drinking fountain',
    'water tap',
    'water point',
    // On the road "water" means something to drink; lakes come along too.
    'water',
  ],
  'toilets': <String>['toilets', 'toilet', 'restroom', 'wc'],
  'bicycle_repair_station': <String>[
    'bike repair station',
    'bicycle repair station',
    'repair station',
  ],
  'bicycle_shop': <String>['bike shop', 'bicycle shop', 'bike store'],
  'bicycle_tube_vending': <String>[
    'tube vending machine',
    'inner tube',
    'bike tube',
    'bicycle tube',
  ],
  'bicycle_rental': <String>['bike rental', 'bicycle rental', 'bike hire'],
  'bicycle_parking': <String>['bike parking', 'bicycle parking'],
  'charging_station': <String>[
    'charging station',
    'e-bike charging',
    'ebike charging',
  ],
  'shelter': <String>['shelter'],
  'cafe': <String>['cafe', 'coffee'],
  'restaurant': <String>['restaurant'],
  'fast_food': <String>['fast food', 'takeaway', 'take-away'],
  'ice_cream': <String>['ice cream', 'gelato'],
  'fuel': <String>['petrol station', 'gas station', 'fuel station'],
  'compressed_air': <String>['air pump', 'tyre air', 'tire air'],
  'bakery': <String>['bakery'],
  'supermarket': <String>['supermarket', 'grocery', 'convenience store'],
  'pharmacy': <String>['pharmacy', 'chemist'],
  'picnic_site': <String>['picnic site', 'picnic area'],
  'camp_site': <String>['campsite', 'camp site', 'camping'],
  'hotel': <String>['hotel'],
  'hostel': <String>['hostel'],
  'alpine_hut': <String>['mountain hut', 'alpine hut'],
  // "train", "bus", "tram", "ferry" start these, so the one word is enough.
  'station': <String>['train station', 'railway station'],
  'bus_stop': <String>['bus stop'],
  'tram_stop': <String>['tram stop', 'streetcar stop'],
  'airport': <String>['airport'],
  'ferry_terminal': <String>['ferry terminal'],
  'hospital': <String>['hospital'],
  'university': <String>['university'],
  'stadium': <String>['sports venue', 'stadium'],
  'mall': <String>['shopping centre', 'shopping center'],
  'viewpoint': <String>['viewpoint'],
  'peak': <String>['summit'],
  'mountain_pass': <String>['mountain pass'],
  'park': <String>['park'],
  'water': <String>['lake', 'river'],
  'beach': <String>['beach'],
  'nature_reserve': <String>['nature reserve'],
  'attraction': <String>['attraction'],
  'museum': <String>['museum'],
  'historic': <String>['historic site'],
  'place_of_worship': <String>['place of worship', 'church'],
  'tower': <String>['tower'],
  'lighthouse': <String>['lighthouse'],
};

/// The kinds found only by asking for them ("bus stop", nearest first), never
/// in the name matches: a tile holds thousands of stops named after the street
/// they stand in, and they would bury the streets and places a name query
/// means. The builder keeps them out of the name index for that reason too.
const Set<String> kindSearchOnlyPoiKinds = <String>{'bus_stop', 'tram_stop'};

/// The kinds [text] asks for: the ones with a keyword that [text] is, or
/// starts.
///
/// [keywords] is the localised table — the label of every kind and the other
/// words that ask for it, lower case, mapped to the kind, or to the kinds,
/// space-separated, for a word that names several ("Haltestelle") — which the
/// widget builds from `AppLocalizations`; the English words above are always
/// searched as well. "bike" names four kinds and gets all four, nearest
/// first; "bakery" names one. Only the whole text is matched against a
/// keyword, so "Busch" and "bus marktplatz" stay name searches.
List<String> kindsForKeyword(String text, Map<String, String> keywords) {
  final typed = foldSearchTerm(text.trim());
  if (typed.isEmpty) return const <String>[];
  final kinds = <String>{};
  void consider(String keyword, String kind) {
    final folded = foldSearchTerm(keyword);
    if (folded == typed || folded.startsWith(typed)) kinds.add(kind);
  }

  for (final entry in englishKindKeywords.entries) {
    for (final keyword in entry.value) {
      consider(keyword, entry.key);
    }
  }
  for (final entry in keywords.entries) {
    for (final kind in entry.value.split(' ')) {
      consider(entry.key, kind);
    }
  }
  return <String>[
    for (final kind in searchPoiKinds)
      if (kinds.contains(kind)) kind,
  ];
}
