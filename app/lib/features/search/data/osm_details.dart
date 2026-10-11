import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/http/user_agent.dart';
import '../domain/osm_place_details.dart';
import 'osm_details_cache.dart';

part 'osm_details.g.dart';

/// The details of a place could not be fetched.
class OsmDetailsException implements Exception {
  /// Creates the exception.
  const OsmDetailsException(this.message, {this.cause});

  /// What went wrong, for the log.
  final String message;

  /// The underlying error, when there was one.
  final Object? cause;

  @override
  String toString() => 'OsmDetailsException: $message';
}

/// Where the place card gets the tags of an OpenStreetMap element.
abstract interface class OsmDetailsSource {
  /// The tags of the element [type] (`node`, `way`, `relation`) [id].
  ///
  /// Empty when it has none or no longer exists; throws
  /// [OsmDetailsException] when the API cannot be reached.
  Future<Map<String, String>> tags(String type, int id);
}

/// Reads an element's tags from the OpenStreetMap API, only when asked.
class OsmDetailsClient implements OsmDetailsSource {
  /// Creates a client; inject [dio] in tests.
  OsmDetailsClient({Dio? dio, this.baseUrl = defaultBaseUrl})
    : _dio =
          dio ??
          velorkiDio(
            BaseOptions(
              connectTimeout: timeout,
              receiveTimeout: timeout,
              sendTimeout: timeout,
            ),
          );

  /// The OpenStreetMap API.
  static const String defaultBaseUrl = 'https://api.openstreetmap.org/api/0.6';

  /// How long a request may take before the card says it failed.
  static const Duration timeout = Duration(seconds: 6);

  /// The API root, without a trailing slash.
  final String baseUrl;

  final Dio _dio;

  /// The URL [details] requests.
  Uri uri(String type, int id) => Uri.parse('$baseUrl/$type/$id.json');

  @override
  Future<Map<String, String>> tags(String type, int id) async {
    Response<String> response;
    try {
      response = await _dio.getUri<String>(
        uri(type, id),
        options: Options(
          responseType: ResponseType.plain,
          // A deleted or unknown element is an answer, not a failure.
          validateStatus: (status) =>
              status != null &&
              ((status >= 200 && status < 300) ||
                  status == 404 ||
                  status == 410),
        ),
      );
    } on DioException catch (e) {
      throw OsmDetailsException('cannot reach the OSM API', cause: e);
    }
    final status = response.statusCode ?? 0;
    return status == 404 || status == 410
        ? const <String, String>{}
        : parseOsmTags(response.data ?? '');
  }

  /// Closes the client.
  void close() => _dio.close();
}

/// The tags of the first element of an OSM API JSON answer.
///
/// Throws [OsmDetailsException] when [body] is not such an answer.
Map<String, String> parseOsmTags(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw OsmDetailsException('OSM answer is not JSON', cause: e);
  }
  if (decoded is! Map || decoded['elements'] is! List) {
    throw const OsmDetailsException('OSM answer has no elements');
  }
  final elements = decoded['elements'] as List;
  if (elements.isEmpty) return const <String, String>{};
  final element = elements.first;
  final tags = element is Map ? element['tags'] : null;
  if (tags is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in tags.entries) '${entry.key}': '${entry.value}',
  };
}

/// The source of place details. Overridden in tests.
@Riverpod(keepAlive: true)
OsmDetailsSource osmDetailsSource(Ref ref) {
  final client = OsmDetailsClient();
  ref.onDispose(client.close);
  return client;
}

/// The details of places: from the device when fetched lately, else from
/// [OsmDetailsSource], kept on the device for next time.
class OsmDetailsRepository {
  /// Creates the repository.
  const OsmDetailsRepository(this._source, this._cache);

  final OsmDetailsSource _source;
  final OsmDetailsCache _cache;

  /// The details of [type] [id] when they were fetched lately, without
  /// asking the network; `null` when they have to be fetched.
  OsmPlaceDetails? cached(String type, int id) {
    final tags = _cache.lookup(type, id);
    return tags == null ? null : OsmPlaceDetails.fromTags(tags);
  }

  /// Fetches the details of [type] [id] and keeps their tags.
  ///
  /// Throws [OsmDetailsException] when they cannot be fetched; a failure is
  /// not kept.
  Future<OsmPlaceDetails> fetch(String type, int id) async {
    final tags = await _source.tags(type, id);
    await _cache.store(type, id, tags);
    return OsmPlaceDetails.fromTags(tags);
  }
}

/// Where the place card gets the details of a place.
@Riverpod(keepAlive: true)
OsmDetailsRepository osmDetailsRepository(Ref ref) => OsmDetailsRepository(
  ref.watch(osmDetailsSourceProvider),
  ref.watch(osmDetailsCacheProvider),
);
