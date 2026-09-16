import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

part 'search_result.freezed.dart';

/// Where a [SearchResult] came from.
enum SearchSource {
  /// The Photon geocoder over the network.
  online,

  /// A `<TILE>.gaz` gazetteer on this device.
  local,
}

/// What kind of thing a [SearchResult] is, as far as the UI cares.
enum SearchKind {
  /// A settlement or an island: city, town, village, hamlet, …
  place,

  /// A street.
  street,

  /// A named point of interest: a cafe, a tap, a peak, a station, …
  poi,

  /// Anything the source did not classify.
  unknown,
}

/// One place the search found, online or on this device.
@freezed
abstract class SearchResult with _$SearchResult {
  const factory SearchResult({
    required String name,
    required LatLng position,

    /// For a local result: the place or admin area it sits in, when the
    /// gazetteer knows one. For an online result: Photon's city or district.
    String? city,
    String? state,
    String? country,

    /// Photon's `osm_key`, e.g. `place`, `highway`, `tourism`.
    String? osmKey,

    /// Photon's `osm_value`, e.g. `village`, `peak`, `attraction`.
    String? osmValue,

    /// Whether this came off the network or off this device.
    @Default(SearchSource.online) SearchSource source,

    /// The row's kind, for the icon.
    @Default(SearchKind.unknown) SearchKind kind,

    /// The exact kind as the source spells it (`village`, `cafe`, `peak`),
    /// which the widget turns into a localised label. `osmValue` for an
    /// online result.
    String? detail,
  }) = _SearchResult;

  const SearchResult._();

  /// City, state and country, joined for the second line of a result row.
  ///
  /// Only used for online results; a local row's second line is built in the
  /// widget, where the localisations are.
  String get subtitle =>
      [city, state, country].where((s) => s != null && s.isNotEmpty).join(', ');
}

/// The kind an online result's `osm_key` stands for.
SearchKind searchKindOfOsmKey(String? osmKey) => switch (osmKey) {
  'place' => SearchKind.place,
  'highway' => SearchKind.street,
  _ => SearchKind.unknown,
};
