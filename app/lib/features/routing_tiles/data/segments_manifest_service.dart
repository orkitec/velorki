import 'package:dio/dio.dart';

import '../../../core/http/user_agent.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart' hide CancelToken;

import '../../../app/app_config.dart';
import 'routing_tiles_repository.dart';

part 'segments_manifest_service.g.dart';

/// BRouter's own segment directory.
///
/// **Development fallback only.** It is used when `VELORKI_SEGMENTS_URL` is
/// empty, so a debug build can download a tile without a mirror of our own;
/// brouter.de is not an app backend and a release build points at the VPS
/// mirror (see `brouter/updater/sync.sh`, which writes the `manifest.json`
/// this service prefers).
const String brouterDeSegmentsUrl = 'https://brouter.de/brouter/segments4';

/// Raised when the segment mirror cannot be read.
class SegmentsManifestException implements Exception {
  /// Creates the failure.
  const SegmentsManifestException(this.message, {this.cause});

  /// What went wrong, in one sentence.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() => 'SegmentsManifestException: $message';
}

/// Reads the list of downloadable rd5 tiles with their sizes and dates.
class SegmentsManifestService {
  /// Creates the service. An empty [segmentsUrl] selects the brouter.de
  /// fallback.
  SegmentsManifestService({required Dio dio, required String segmentsUrl})
    // Named parameters cannot be private, so this cannot be an initialising
    // formal.
    // ignore: prefer_initializing_formals
    : _dio = dio,
      _segmentsUrl = segmentsUrl.trim();

  final Dio _dio;
  final String _segmentsUrl;

  /// Whether the brouter.de directory listing is being used because no mirror
  /// is configured.
  bool get isFallback => _segmentsUrl.isEmpty;

  /// The directory the tiles are fetched from, without a trailing slash.
  String get baseUrl {
    final url = isFallback ? brouterDeSegmentsUrl : _segmentsUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Where one tile is downloaded from.
  Uri tileUrl(TileName tile) => Uri.parse('$baseUrl/${tile.fileName}');

  /// Fetches the manifest: `manifest.json` from our own mirror, or the
  /// scraped directory listing from brouter.de.
  Future<SegmentsManifest> fetch() async {
    if (isFallback) return _fetchDirectoryListing();
    final Response<Object?> response;
    try {
      response = await _dio.get<Object?>('$baseUrl/manifest.json');
    } on DioException catch (e) {
      throw SegmentsManifestException(
        'The segment mirror at $baseUrl could not be reached.',
        cause: e,
      );
    }
    try {
      return SegmentsManifest.parse(response.data);
    } on Object catch (e) {
      throw SegmentsManifestException(
        'The manifest at $baseUrl/manifest.json is not readable.',
        cause: e,
      );
    }
  }

  Future<SegmentsManifest> _fetchDirectoryListing() async {
    final Response<String> response;
    try {
      response = await _dio.get<String>('$baseUrl/');
    } on DioException catch (e) {
      throw SegmentsManifestException(
        'The segment listing at $baseUrl could not be reached.',
        cause: e,
      );
    }
    try {
      return SegmentsManifest.parseDirectoryListing(response.data ?? '');
    } on Object catch (e) {
      throw SegmentsManifestException(
        'The segment listing at $baseUrl is not readable.',
        cause: e,
      );
    }
  }
}

/// The dio the tile mirror is talked to with.
///
/// Its own instance: downloads are long, so the connect and receive timeouts
/// are nothing like the ones the API client wants.
@Riverpod(keepAlive: true)
Dio segmentsDio(Ref ref) {
  final dio = Dio(
    velorkiBaseOptions(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 2),
        responseType: ResponseType.json,
      ),
    ),
  );
  ref.onDispose(dio.close);
  return dio;
}

/// The mirror configured in `VELORKI_SEGMENTS_URL`, or the fallback.
@Riverpod(keepAlive: true)
SegmentsManifestService segmentsManifestService(Ref ref) =>
    SegmentsManifestService(
      dio: ref.watch(segmentsDioProvider),
      segmentsUrl: ref.watch(effectiveConfigProvider).segmentsUrl,
    );

/// The manifest, fetched once and refreshable.
///
/// Fetching it also re-marks the downloaded tiles the mirror has rebuilt as
/// `stale`, which is the only place that comparison happens.
@Riverpod(keepAlive: true)
class SegmentsManifestSource extends _$SegmentsManifestSource {
  @override
  Future<SegmentsManifest> build() async {
    final manifest = await ref.watch(segmentsManifestServiceProvider).fetch();
    final repository = await ref.read(routingTilesRepositoryProvider.future);
    await repository.applyManifest(manifest);
    return manifest;
  }

  /// Fetches the manifest again, e.g. after "Check for updates".
  Future<void> refresh() async {
    state = const AsyncLoading<SegmentsManifest>();
    state = await AsyncValue.guard(build);
  }
}
