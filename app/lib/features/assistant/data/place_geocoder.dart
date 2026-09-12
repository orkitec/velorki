import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../search/data/photon_client.dart';
import '../../search/domain/search_result.dart';
import '../domain/intent_resolver.dart';

/// [PlaceGeocoder] over the app's Photon client.
///
/// The adapter exists so [IntentResolver] does not depend on the search
/// feature's HTTP client, and so a test can hand the resolver canned places
/// without a `Dio`.
class PhotonPlaceGeocoder implements PlaceGeocoder {
  /// Creates the adapter over [client].
  const PhotonPlaceGeocoder(this._client, {this.lang});

  final PhotonClient _client;

  /// The language Photon should answer in, e.g. `de`.
  final String? lang;

  @override
  Future<List<SearchResult>> lookup(
    String query, {
    LatLng? bias,
    int limit = 5,
  }) => _client.search(query, limit: limit, bias: bias, lang: lang);
}

/// The geocoder the assistant resolves names with, or `null` when this build
/// has no Photon URL.
final placeGeocoderProvider = Provider<PlaceGeocoder?>((ref) {
  final client = ref.watch(photonClientProvider);
  return client == null ? null : PhotonPlaceGeocoder(client);
});

/// The resolver, or `null` when there is no geocoder to resolve with.
final intentResolverProvider = Provider<IntentResolver?>((ref) {
  final geocoder = ref.watch(placeGeocoderProvider);
  return geocoder == null ? null : IntentResolver(geocoder: geocoder);
});
