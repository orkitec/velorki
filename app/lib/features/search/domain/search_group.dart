import 'package:flutter/foundation.dart';

import 'search_result.dart';

/// The eight buckets the rider can reorder and switch off in Settings →
/// Search.
///
/// Every gazetteer kind belongs to exactly one of them (or to none, when the
/// file was built by a newer builder than this app knows). The declaration
/// order is the default priority.
enum SearchGroup {
  /// Cities, towns, villages, hamlets, islands: everything in `places`.
  places,

  /// Streets, and the house numbers on them.
  streets,

  /// Attractions, museums, historic sites, churches, towers, named buildings.
  landmarks,

  /// What a rider stops for: taps, cafes, bike shops, repair stations, rental,
  /// parking, charging, shelters, bakeries, supermarkets, toilets.
  cyclingStops,

  /// Campsites, hotels, hostels, mountain huts.
  overnight,

  /// Peaks, passes, viewpoints, parks, water, beaches, reserves, picnic sites.
  nature,

  /// Stations, airports, ferry terminals.
  transport,

  /// Hospitals, pharmacies, universities, sports venues, shopping centres.
  services;

  /// The group named [name], or `null` when this build does not know it.
  static SearchGroup? byName(String name) {
    for (final group in values) {
      if (group.name == name) return group;
    }
    return null;
  }
}

/// Which group a `pois.kind` belongs to.
///
/// Kinds missing here are landmark-ish leftovers from a newer builder: they
/// stay in the results and rank last, because a rider who switched nothing off
/// should never lose a row to a kind this build has not heard of.
const Map<String, SearchGroup> searchGroupOfPoiKind = <String, SearchGroup>{
  // Landmarks.
  'building': SearchGroup.landmarks,
  'attraction': SearchGroup.landmarks,
  'museum': SearchGroup.landmarks,
  'historic': SearchGroup.landmarks,
  'place_of_worship': SearchGroup.landmarks,
  'tower': SearchGroup.landmarks,
  'lighthouse': SearchGroup.landmarks,
  // Cycling stops.
  'cafe': SearchGroup.cyclingStops,
  'drinking_water': SearchGroup.cyclingStops,
  'bicycle_repair_station': SearchGroup.cyclingStops,
  'bicycle_shop': SearchGroup.cyclingStops,
  'bicycle_rental': SearchGroup.cyclingStops,
  'bicycle_parking': SearchGroup.cyclingStops,
  'charging_station': SearchGroup.cyclingStops,
  'shelter': SearchGroup.cyclingStops,
  'bakery': SearchGroup.cyclingStops,
  'supermarket': SearchGroup.cyclingStops,
  'toilets': SearchGroup.cyclingStops,
  // Overnight.
  'camp_site': SearchGroup.overnight,
  'hotel': SearchGroup.overnight,
  'hostel': SearchGroup.overnight,
  'alpine_hut': SearchGroup.overnight,
  // Nature.
  'peak': SearchGroup.nature,
  'mountain_pass': SearchGroup.nature,
  'viewpoint': SearchGroup.nature,
  'park': SearchGroup.nature,
  'water': SearchGroup.nature,
  'beach': SearchGroup.nature,
  'nature_reserve': SearchGroup.nature,
  'picnic_site': SearchGroup.nature,
  // Transport.
  'station': SearchGroup.transport,
  'airport': SearchGroup.transport,
  'ferry_terminal': SearchGroup.transport,
  // Services.
  'hospital': SearchGroup.services,
  'pharmacy': SearchGroup.services,
  'university': SearchGroup.services,
  'stadium': SearchGroup.services,
  'mall': SearchGroup.services,
};

/// The group [result] belongs to, or `null` when it has none.
SearchGroup? searchGroupOf(SearchResult result) => switch (result.kind) {
  SearchKind.place => SearchGroup.places,
  SearchKind.street => SearchGroup.streets,
  SearchKind.poi => searchGroupOfPoiKind[result.detail],
  SearchKind.unknown => null,
};

/// Settings → Search: which groups the offline search shows, and in which
/// order it prefers them.
///
/// Everything is on, in the declaration order of [SearchGroup], until the
/// rider says otherwise.
@immutable
class SearchPreferences {
  /// Creates the preferences.
  const SearchPreferences({
    this.order = SearchGroup.values,
    this.disabled = const <SearchGroup>{},
  });

  /// Every group, most wanted first. Ties on bm25 go to the earlier group.
  final List<SearchGroup> order;

  /// The groups whose rows are left out of the local results.
  final Set<SearchGroup> disabled;

  /// What a rider who never opened the page gets.
  static const SearchPreferences defaults = SearchPreferences();

  /// Whether rows of [group] are shown at all. A row without a group always
  /// is.
  bool isEnabled(SearchGroup? group) =>
      group == null || !disabled.contains(group);

  /// Where [group] sits in [order]; an unknown or missing group ranks last.
  int rankOf(SearchGroup? group) {
    if (group == null) return order.length;
    final index = order.indexOf(group);
    return index < 0 ? order.length : index;
  }

  /// A copy with the named fields replaced.
  SearchPreferences copyWith({
    List<SearchGroup>? order,
    Set<SearchGroup>? disabled,
  }) => SearchPreferences(
    order: order ?? this.order,
    disabled: disabled ?? this.disabled,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchPreferences &&
          listEquals(other.order, order) &&
          setEquals(other.disabled, disabled);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(order), Object.hashAllUnordered(disabled));

  @override
  String toString() =>
      'SearchPreferences(order: ${order.map((g) => g.name).join(', ')}, '
      'disabled: ${disabled.map((g) => g.name).join(', ')})';
}
