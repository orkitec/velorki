import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/app_config.dart';
import '../domain/search_result.dart';

part 'photon_client.g.dart';

/// A geocoder request that produced no results.
class SearchException implements Exception {
  /// Creates a search exception.
  const SearchException(this.message, {this.cause});

  /// What went wrong, for the log.
  final String message;

  /// The underlying error, when there was one.
  final Object? cause;

  @override
  String toString() => 'SearchException: $message';
}

/// Photon (komoot) autocomplete geocoder.
///
/// Photon is the one OSM geocoder whose terms allow autocomplete; Nominatim
/// forbids it. The app talks to it directly, never through our relay.
class PhotonClient {
  /// Creates a client for the Photon instance at [baseUrl].
  ///
  /// [baseUrl] is the server root, with or without a trailing slash; the
  /// `/api` path is appended. Inject [dio] in tests.
  PhotonClient(String baseUrl, {Dio? dio})
    : _base = _normalizeBase(baseUrl),
      _dio = dio ?? Dio();

  final Uri _base;
  final Dio _dio;

  /// How many results the planner asks for.
  static const int defaultLimit = 8;

  /// Languages the public Photon instance accepts for `lang`. Anything else
  /// (including region-qualified locales such as `en_US`) is answered with
  /// HTTP 400, so the parameter is dropped and Photon falls back to its
  /// default names.
  static const Set<String> supportedLanguages = {'de', 'en', 'fr'};

  /// Reduces a locale tag (`en_US`, `de-DE`, `en`) to a Photon language, or
  /// null when Photon does not support it.
  static String? photonLanguage(String? locale) {
    if (locale == null || locale.isEmpty) return null;
    final language = locale.split(RegExp('[-_]')).first.toLowerCase();
    return supportedLanguages.contains(language) ? language : null;
  }

  /// The server root this client talks to.
  Uri get baseUri => _base;

  /// The URL a [search] would request. Public so tests can assert it.
  Uri buildUri(
    String query, {
    int limit = defaultLimit,
    String? lang,
    LatLng? bias,
  }) => _base.replace(
    path: '${_base.path}/api',
    queryParameters: <String, String>{
      'q': query,
      'limit': '$limit',
      'lang': ?photonLanguage(lang),
      if (bias != null) 'lat': bias.lat.toString(),
      if (bias != null) 'lon': bias.lon.toString(),
    },
  );

  /// Searches for [query], biased towards [bias] when the map centre is known.
  ///
  /// Throws [SearchException] when the server cannot be reached or answers
  /// with something that is not a Photon `FeatureCollection`.
  Future<List<SearchResult>> search(
    String query, {
    int limit = defaultLimit,
    String? lang,
    LatLng? bias,
    CancelToken? cancelToken,
  }) async {
    final uri = buildUri(query, limit: limit, lang: lang, bias: bias);
    Response<String> response;
    try {
      response = await _dio.getUri<String>(
        uri,
        options: Options(responseType: ResponseType.plain),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw SearchException('cannot reach Photon at $uri', cause: e);
    }
    final body = response.data;
    if (body == null || body.isEmpty) {
      throw const SearchException('empty answer from Photon');
    }
    return parsePhotonResponse(body);
  }

  /// Closes the client when it created its own [Dio].
  void close() => _dio.close();

  static Uri _normalizeBase(String baseUrl) {
    final uri = Uri.parse(baseUrl.trim());
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: path, query: '', fragment: '');
  }
}

/// Parses Photon's GeoJSON answer.
///
/// Features without usable coordinates are skipped rather than failing the
/// whole search: one odd entry should not hide the other seven.
List<SearchResult> parsePhotonResponse(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw SearchException('Photon answer is not JSON', cause: e);
  }
  if (decoded is! Map<String, dynamic> || decoded['features'] is! List) {
    throw const SearchException('Photon answer is not a FeatureCollection');
  }
  final out = <SearchResult>[];
  for (final feature in decoded['features'] as List) {
    if (feature is! Map<String, dynamic>) continue;
    final geometry = feature['geometry'];
    final props = feature['properties'];
    if (geometry is! Map || props is! Map) continue;
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) continue;
    final lon = _asDouble(coords[0]);
    final lat = _asDouble(coords[1]);
    if (lon == null || lat == null) continue;
    final name = _asString(props['name']) ?? _asString(props['street']);
    if (name == null || name.isEmpty) continue;
    out.add(
      SearchResult(
        name: name,
        position: LatLng(lat, lon),
        city: _asString(props['city']) ?? _asString(props['district']),
        state: _asString(props['state']),
        country: _asString(props['country']),
        osmKey: _asString(props['osm_key']),
        osmValue: _asString(props['osm_value']),
      ),
    );
  }
  return out;
}

double? _asDouble(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

String? _asString(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// The geocoder, or `null` when no Photon URL is configured.
@Riverpod(keepAlive: true)
PhotonClient? photonClient(Ref ref) {
  final url = ref.watch(effectiveConfigProvider).photonUrl;
  if (url.isEmpty) return null;
  final client = PhotonClient(url);
  ref.onDispose(client.close);
  return client;
}
