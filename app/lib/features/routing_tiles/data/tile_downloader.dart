import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart' hide CancelToken;

import '../domain/sha256.dart';
import 'routing_tiles_repository.dart';
import 'segments_manifest_service.dart';

part 'tile_downloader.g.dart';

/// How far one tile download has got.
@immutable
class TileDownloadProgress {
  /// Creates a progress report.
  const TileDownloadProgress({
    required this.tile,
    required this.received,
    required this.total,
  });

  /// Which tile is being downloaded.
  final TileName tile;

  /// Bytes on disk, including what a resumed `.part` already held.
  final int received;

  /// Bytes the finished file will have, or 0 when the mirror did not say.
  final int total;

  /// 0..1, or `null` when the total is unknown.
  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;

  @override
  String toString() => 'TileDownloadProgress($tile, $received/$total)';
}

/// Why a tile download failed.
enum TileDownloadFailure {
  /// The mirror could not be reached, or answered with an error.
  network,

  /// The file is not the size the manifest promised.
  sizeMismatch,

  /// The file does not hash to the manifest's `sha256`.
  checksumMismatch,

  /// The rider cancelled it.
  cancelled,

  /// The file could not be written.
  storage,
}

/// A tile download that did not finish.
class TileDownloadException implements Exception {
  /// Creates the failure.
  const TileDownloadException(this.kind, this.message, {this.cause});

  /// What kind of failure it was.
  final TileDownloadFailure kind;

  /// What went wrong, in one sentence.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() => 'TileDownloadException(${kind.name}): $message';
}

/// Downloads rd5 segment tiles, resumably.
///
/// The bytes go into `<name>.rd5.part`; only a file that has the size (and,
/// when the manifest carries one, the SHA-256) the manifest promises is
/// renamed to `<name>.rd5`, so a half-downloaded tile can never be picked up
/// by [RoutingTilesRepository.readyTiles] and routed on. An interrupted
/// download keeps its `.part` and the next attempt continues it with a
/// `Range` request; a mirror that ignores the range simply starts again.
///
/// **No Wi-Fi check.** `connectivity_plus` is not a dependency of this app, so
/// the downloader does not know what the phone is connected to; the screen
/// says so instead of pretending. See `docs/OPEN_ITEMS.md`.
class TileDownloader {
  /// Creates a downloader writing into [segmentsDir] and [gazetteerDir].
  TileDownloader({
    required Dio dio,
    required Directory segmentsDir,
    required Directory gazetteerDir,
    required Uri Function(TileName tile) urlFor,
    required Uri Function(TileName tile) gazetteerUrlFor,
  }) // Named parameters cannot be private, so these cannot be initialising
    // formals.
    // ignore: prefer_initializing_formals
    : _dio = dio,
       // ignore: prefer_initializing_formals
       _segmentsDir = segmentsDir,
       // ignore: prefer_initializing_formals
       _gazetteerDir = gazetteerDir,
       // ignore: prefer_initializing_formals
       _urlFor = urlFor,
       // ignore: prefer_initializing_formals
       _gazetteerUrlFor = gazetteerUrlFor;

  final Dio _dio;
  final Directory _segmentsDir;
  final Directory _gazetteerDir;
  final Uri Function(TileName tile) _urlFor;
  final Uri Function(TileName tile) _gazetteerUrlFor;
  final StreamController<TileDownloadProgress> _progress =
      StreamController<TileDownloadProgress>.broadcast();

  /// Progress of whatever is being downloaded right now.
  Stream<TileDownloadProgress> get progress => _progress.stream;

  /// Downloads [entry] and returns the finished `.rd5` file.
  ///
  /// Pass [cancelToken] to abort; the partial file stays behind so the next
  /// call resumes it.
  Future<File> download(SegmentEntry entry, {CancelToken? cancelToken}) async {
    await _segmentsDir.create(recursive: true);
    return _downloadTo(
      File('${_segmentsDir.path}/${entry.fileName}'),
      url: _urlFor(entry.tile),
      fileName: entry.fileName,
      bytes: entry.bytes,
      sha256: entry.sha256,
      onProgress: (received) => _emit(entry, received),
      cancelToken: cancelToken,
    );
  }

  /// Downloads the offline gazetteer [entry] into the gazetteer directory.
  ///
  /// Same resumable fetch and the same verification as a tile, but the file is
  /// a couple of hundred kilobytes, so no progress is reported. Its checksum
  /// is mandatory, so a truncated or rewritten file can never be opened as a
  /// search index.
  Future<File> downloadGazetteer(
    GazetteerEntry entry, {
    CancelToken? cancelToken,
  }) async {
    await _gazetteerDir.create(recursive: true);
    return _downloadTo(
      File('${_gazetteerDir.path}/${entry.fileName}'),
      url: _gazetteerUrlFor(entry.tile),
      fileName: entry.fileName,
      bytes: entry.bytes,
      sha256: entry.sha256,
      cancelToken: cancelToken,
    );
  }

  /// Closes the progress stream.
  void dispose() => unawaited(_progress.close());

  Future<File> _downloadTo(
    File target, {
    required Uri url,
    required String fileName,
    required int bytes,
    required String? sha256,
    void Function(int received)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final part = File('${target.path}.part');

    var offset = part.existsSync() ? await part.length() : 0;
    if (bytes > 0 && offset > bytes) {
      // Longer than the mirror says: it cannot be a prefix of this file.
      await part.delete();
      offset = 0;
    }
    onProgress?.call(offset);

    if (bytes == 0 || offset < bytes) {
      await _fetch(
        url: url,
        fileName: fileName,
        part: part,
        offset: offset,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    await _verify(part, fileName: fileName, bytes: bytes, sha256: sha256);

    if (target.existsSync()) await target.delete();
    return part.rename(target.path);
  }

  Future<void> _fetch({
    required Uri url,
    required String fileName,
    required File part,
    required int offset,
    void Function(int received)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final Response<ResponseBody> response;
    try {
      response = await _dio.getUri<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: offset > 0
              ? <String, Object>{HttpHeaders.rangeHeader: 'bytes=$offset-'}
              : null,
          validateStatus: (status) => status == 200 || status == 206,
        ),
      );
    } on DioException catch (e) {
      throw _dioFailure(fileName, e);
    }

    // 200 means the mirror ignored the range and is sending the whole file.
    final resumed = response.statusCode == 206;
    final start = resumed ? offset : 0;
    var received = start;

    final sink = part.openWrite(
      mode: start > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received);
      }
      await sink.flush();
    } on DioException catch (e) {
      throw _dioFailure(fileName, e);
    } on FileSystemException catch (e) {
      throw TileDownloadException(
        TileDownloadFailure.storage,
        'There is no room for $fileName on this device.',
        cause: e,
      );
    } finally {
      await sink.close();
    }
  }

  Future<void> _verify(
    File part, {
    required String fileName,
    required int bytes,
    required String? sha256,
  }) async {
    final size = await part.length();
    if (bytes > 0 && size != bytes) {
      await part.delete();
      throw TileDownloadException(
        TileDownloadFailure.sizeMismatch,
        '$fileName arrived with $size bytes instead of $bytes.',
      );
    }
    if (sha256 != null && sha256.isNotEmpty) {
      final actual = await sha256OfFile(part);
      if (actual.toLowerCase() != sha256.toLowerCase()) {
        await part.delete();
        throw TileDownloadException(
          TileDownloadFailure.checksumMismatch,
          '$fileName does not match the checksum in the manifest.',
        );
      }
    }
  }

  void _emit(SegmentEntry entry, int received) {
    if (_progress.isClosed) return;
    _progress.add(
      TileDownloadProgress(
        tile: entry.tile,
        received: received,
        total: entry.bytes,
      ),
    );
  }

  TileDownloadException _dioFailure(String fileName, DioException e) =>
      e.type == DioExceptionType.cancel
      ? TileDownloadException(
          TileDownloadFailure.cancelled,
          'The download of $fileName was cancelled.',
          cause: e,
        )
      : TileDownloadException(
          TileDownloadFailure.network,
          '$fileName could not be downloaded '
          '(${e.response?.statusCode ?? e.type.name}).',
          cause: e,
        );
}

/// The app's [TileDownloader], writing into the segments directory.
@Riverpod(keepAlive: true)
Future<TileDownloader> tileDownloader(Ref ref) async {
  final repository = await ref.watch(routingTilesRepositoryProvider.future);
  final service = ref.watch(segmentsManifestServiceProvider);
  final downloader = TileDownloader(
    dio: ref.watch(segmentsDioProvider),
    segmentsDir: repository.segmentsDir,
    gazetteerDir: repository.gazetteerDir,
    urlFor: service.tileUrl,
    gazetteerUrlFor: service.gazetteerUrl,
  );
  ref.onDispose(downloader.dispose);
  return downloader;
}
