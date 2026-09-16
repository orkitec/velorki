import 'dart:convert';

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

/// One release of a snapshot: a base URL with its own `manifest.json`.
class _Shard {
  const _Shard(this.name, this.baseUrl);

  /// The release tag, or the base URL when the pointer names no tag.
  final String name;

  /// Where this shard's tiles and manifest live, without a trailing slash.
  final String baseUrl;
}

/// Reads the list of downloadable rd5 tiles with their sizes and dates.
///
/// `VELORKI_SEGMENTS_URL` names either a directory holding `manifest.json`
/// and the tiles, or a pointer file such as the mirror's `latest.json`, which
/// carries the `baseUrl` of the current snapshot. A pointer lets the mirror
/// move to a fresh snapshot without an app release.
///
/// A snapshot bigger than one GitHub release (at most 1000 assets, and a tile
/// is two of them) is split into shards, each its own release with its own
/// `manifest.json` listing only its tiles. The pointer's `shards` array names
/// them all; every shard is read and the tiles are merged into one manifest,
/// each entry remembering the shard it is served from. One unreadable shard
/// fails the whole fetch: a manifest missing a shard would silently hide
/// whole regions from the rider.
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
  String? _resolvedBase;

  /// Whether the brouter.de directory listing is being used because no mirror
  /// is configured.
  bool get isFallback => _segmentsUrl.isEmpty;

  /// Whether the configured URL is a pointer file rather than a directory.
  bool get isPointer => _segmentsUrl.endsWith('.json');

  /// The directory tiles without a base URL of their own are fetched from,
  /// without a trailing slash.
  ///
  /// For a pointer this is the first shard of the snapshot it named the last
  /// time [fetch] ran; before that, the pointer's own directory, which holds
  /// no tiles. Every download follows a manifest fetch, so that state is
  /// never used.
  String get baseUrl {
    final url = isFallback
        ? brouterDeSegmentsUrl
        : isPointer
        ? (_resolvedBase ??
              _segmentsUrl.substring(0, _segmentsUrl.lastIndexOf('/')))
        : _segmentsUrl;
    return _withoutTrailingSlash(url);
  }

  /// Where one tile is downloaded from: its own shard, or the default base.
  Uri tileUrl(SegmentEntry entry) =>
      Uri.parse('${_baseFor(entry)}/${entry.fileName}');

  /// Where one tile's offline gazetteer is downloaded from.
  Uri gazetteerUrl(SegmentEntry entry) =>
      Uri.parse('${_baseFor(entry)}/${entry.tile.gazetteerFileName}');

  /// Fetches the manifest: `manifest.json` from every shard of our own
  /// mirror, or the scraped directory listing from brouter.de.
  Future<SegmentsManifest> fetch() async {
    if (isFallback) return _fetchDirectoryListing();
    if (!isPointer) return _fetchManifest(baseUrl);
    return _fetchSnapshot(await _readPointer());
  }

  /// Reads every shard the pointer names and merges them into one manifest.
  Future<SegmentsManifest> _fetchSnapshot(Map<Object?, Object?> pointer) async {
    final shards = _shardsOf(pointer);
    _resolvedBase = shards.first.baseUrl;
    final manifests = await Future.wait(<Future<SegmentsManifest>>[
      for (final shard in shards) _fetchManifest(shard.baseUrl, shard: shard),
    ]);

    final tiles = <SegmentEntry>[];
    final seen = <TileName>{};
    for (var i = 0; i < shards.length; i++) {
      for (final entry in manifests[i].tiles) {
        // A tile listed by two shards is served by the first one that has it.
        if (!seen.add(entry.tile)) continue;
        tiles.add(entry.withBaseUrl(shards[i].baseUrl));
      }
    }
    final first = manifests.first;
    return SegmentsManifest(
      tiles: tiles,
      formatVersion: _string(pointer['formatVersion']) ?? first.formatVersion,
      brouterVersion:
          _string(pointer['brouterVersion']) ?? first.brouterVersion,
      source: _string(pointer['source']) ?? first.source,
      generatedAt:
          DateTime.tryParse(_string(pointer['generatedAt']) ?? '')?.toUtc() ??
          first.generatedAt,
    );
  }

  /// Fetches and parses one `manifest.json`.
  ///
  /// [shard] names the release in the failure message, so a rider (and the
  /// log) learns which part of the snapshot is missing.
  Future<SegmentsManifest> _fetchManifest(String base, {_Shard? shard}) async {
    final what = shard == null ? 'segment mirror' : 'shard ${shard.name}';
    final Response<Object?> response;
    try {
      response = await _dio.get<Object?>('$base/manifest.json');
    } on DioException catch (e) {
      throw SegmentsManifestException(
        'The $what at $base could not be reached.',
        cause: e,
      );
    }
    try {
      return SegmentsManifest.parse(_decoded(response.data));
    } on Object catch (e) {
      throw SegmentsManifestException(
        'The manifest of the $what at $base/manifest.json is not readable.',
        cause: e,
      );
    }
  }

  /// Reads the pointer file and returns what it says.
  Future<Map<Object?, Object?>> _readPointer() async {
    final Response<Object?> response;
    try {
      response = await _dio.get<Object?>(_segmentsUrl);
    } on DioException catch (e) {
      throw SegmentsManifestException(
        'The tile mirror pointer at $_segmentsUrl could not be reached.',
        cause: e,
      );
    }
    final Object? data;
    try {
      data = _decoded(response.data);
    } on Object catch (e) {
      throw SegmentsManifestException(
        'The tile mirror pointer at $_segmentsUrl is not readable.',
        cause: e,
      );
    }
    if (data is! Map) {
      throw SegmentsManifestException(
        'The tile mirror pointer at $_segmentsUrl is not readable.',
      );
    }
    return data;
  }

  /// The releases a pointer names, in the order it lists them.
  ///
  /// A pointer without a `shards` array is a one-shard snapshot described by
  /// its own `baseUrl`, which is what a mirror wrote before sharding existed.
  List<_Shard> _shardsOf(Map<Object?, Object?> pointer) {
    final out = <_Shard>[];
    final rows = pointer['shards'];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        final url = _string(row['baseUrl']);
        if (url == null) continue;
        out.add(_Shard(_string(row['tag']) ?? url, _withoutTrailingSlash(url)));
      }
    }
    if (out.isEmpty) {
      final url = _string(pointer['baseUrl']);
      if (url != null) {
        out.add(
          _Shard(_string(pointer['tag']) ?? url, _withoutTrailingSlash(url)),
        );
      }
    }
    if (out.isEmpty) {
      throw SegmentsManifestException(
        'The tile mirror pointer at $_segmentsUrl names no snapshot.',
      );
    }
    return out;
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

  String _baseFor(SegmentEntry entry) {
    final base = entry.baseUrl;
    return base == null || base.isEmpty ? baseUrl : _withoutTrailingSlash(base);
  }

  /// GitHub serves the raw JSON as `text/plain`, so dio hands over a string
  /// rather than a decoded map.
  static Object? _decoded(Object? data) =>
      data is String ? jsonDecode(data) : data;

  static String _withoutTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  static String? _string(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
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
