import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

part 'search_result.freezed.dart';

/// One place the geocoder found.
@freezed
abstract class SearchResult with _$SearchResult {
  const factory SearchResult({
    required String name,
    required LatLng position,
    String? city,
    String? state,
    String? country,

    /// Photon's `osm_key`, e.g. `place`, `highway`, `tourism`.
    String? osmKey,

    /// Photon's `osm_value`, e.g. `village`, `peak`, `attraction`.
    String? osmValue,
  }) = _SearchResult;

  const SearchResult._();

  /// City, state and country, joined for the second line of a result row.
  String get subtitle =>
      [city, state, country].where((s) => s != null && s.isNotEmpty).join(', ');
}
