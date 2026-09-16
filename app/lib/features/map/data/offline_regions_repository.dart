import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/app_config.dart';
import '../../../core/db/daos/offline_regions_dao.dart';
import '../../../core/db/database.dart';

part 'offline_regions_repository.g.dart';

/// Zoom range a downloaded region covers.
///
/// 6 keeps a country-level overview available offline, 15 is the last zoom
/// with full street detail in the OpenFreeMap styles; 16+ would multiply the
/// tile count for very little extra information.
const double offlineMinZoom = 6;

/// See [offlineMinZoom].
const double offlineMaxZoom = 15;

/// What to download.
@immutable
class OfflineRegionSpec {
  const OfflineRegionSpec({
    required this.name,
    required this.bounds,
    required this.styleUrl,
    this.minZoom = offlineMinZoom,
    this.maxZoom = offlineMaxZoom,
  });

  final String name;
  final BoundingBox bounds;
  final String styleUrl;
  final double minZoom;
  final double maxZoom;

  @override
  String toString() =>
      'OfflineRegionSpec($name, $bounds, z$minZoom-$maxZoom, $styleUrl)';
}

/// How far a download has got.
@immutable
class OfflineDownloadProgress {
  const OfflineDownloadProgress({
    required this.fraction,
    required this.completedBytes,
  });

  /// 0..1, as reported by MapLibre.
  final double fraction;

  /// Bytes written so far.
  final int completedBytes;

  @override
  String toString() =>
      'OfflineDownloadProgress(${(fraction * 100).round()}%, $completedBytes B)';
}

/// What a finished download left behind.
@immutable
class OfflineDownloadResult {
  const OfflineDownloadResult({
    required this.maplibreRegionId,
    required this.sizeBytes,
  });

  final int maplibreRegionId;
  final int sizeBytes;
}

/// Raised when MapLibre refuses or aborts a download.
class OfflineDownloadException implements Exception {
  OfflineDownloadException(this.message);

  final String message;

  @override
  String toString() => 'OfflineDownloadException: $message';
}

/// The slice of MapLibre's offline manager the repository uses.
///
/// It exists so the repository can be tested without the plugin: the real
/// calls are top-level functions on a method channel, which a unit test has no
/// way to satisfy.
abstract interface class OfflineMapApi {
  /// Downloads [spec], reporting progress, and completes when it is done.
  Future<OfflineDownloadResult> download(
    OfflineRegionSpec spec, {
    void Function(OfflineDownloadProgress progress)? onProgress,
  });

  /// Removes the region MapLibre knows as [maplibreRegionId].
  Future<void> delete(int maplibreRegionId);

  /// Ids of every region MapLibre currently holds.
  Future<List<int>> regionIds();
}

/// [OfflineMapApi] over maplibre_gl's global offline functions.
class MaplibreOfflineMapApi implements OfflineMapApi {
  const MaplibreOfflineMapApi();

  @override
  Future<OfflineDownloadResult> download(
    OfflineRegionSpec spec, {
    void Function(OfflineDownloadProgress progress)? onProgress,
  }) async {
    final definition = ml.OfflineRegionDefinition(
      bounds: ml.LatLngBounds(
        southwest: ml.LatLng(spec.bounds.south, spec.bounds.west),
        northeast: ml.LatLng(spec.bounds.north, spec.bounds.east),
      ),
      mapStyleUrl: spec.styleUrl,
      minZoom: spec.minZoom,
      maxZoom: spec.maxZoom,
    );
    final finished = Completer<void>();
    var lastBytes = 0;
    final region = await ml.downloadOfflineRegion(
      definition,
      metadata: <String, dynamic>{'name': spec.name},
      onEvent: (event) {
        switch (event) {
          case ml.InProgress(:final progress, :final completedResourceSize):
            lastBytes = completedResourceSize;
            onProgress?.call(
              OfflineDownloadProgress(
                fraction: (progress / 100).clamp(0, 1).toDouble(),
                completedBytes: completedResourceSize,
              ),
            );
          case ml.Success():
            if (!finished.isCompleted) finished.complete();
          case ml.Error(:final cause):
            if (!finished.isCompleted) {
              finished.completeError(
                OfflineDownloadException(cause.message ?? cause.code),
              );
            }
        }
      },
    );
    await finished.future;
    var sizeBytes = lastBytes;
    try {
      final status = await ml.getOfflineRegionStatus(region.id);
      sizeBytes = status.completedResourceSize;
    } on Object {
      // Keep the size from the last progress event.
    }
    return OfflineDownloadResult(
      maplibreRegionId: region.id,
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<void> delete(int maplibreRegionId) async {
    await ml.deleteOfflineRegion(maplibreRegionId);
    // Tiles shared with the ambient cache survive the region; drop them too,
    // otherwise "delete" frees almost nothing.
    await ml.clearAmbientCache();
  }

  @override
  Future<List<int>> regionIds() async {
    final regions = await ml.getListOfRegions();
    return regions.map((r) => r.id).toList();
  }
}

/// Downloaded map areas: the MapLibre offline packs plus the `offline_regions`
/// rows that name them and remember their size.
class OfflineRegionsRepository {
  OfflineRegionsRepository({
    required OfflineRegionsDao dao,
    required OfflineMapApi api,
    String Function()? idFactory,
    DateTime Function()? clock,
  }) // Named parameters cannot be private, so these cannot be initialising
    // formals.
    // ignore: prefer_initializing_formals
    : _dao = dao,
       // ignore: prefer_initializing_formals
       _api = api,
       _idFactory = idFactory ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final OfflineRegionsDao _dao;
  final OfflineMapApi _api;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  /// How old an area has to be before a refresh is offered. OpenFreeMap
  /// rebuilds weekly, but a refresh is a full download again, so it is only
  /// worth it once the map has moved on noticeably.
  static const Duration refreshAfter = Duration(days: 56);

  /// Whether [row] is old enough for a refresh at [now]. An area without a
  /// date predates the column and is treated as old.
  static bool isRefreshDue(OfflineRegionRow row, DateTime now) {
    final downloadedAt = row.downloadedAt;
    return downloadedAt == null || now.difference(downloadedAt) >= refreshAfter;
  }

  /// Every stored region, alphabetically, updated as rows change.
  Stream<List<OfflineRegionRow>> watchRegions() => _dao.watchRegions();

  /// Every stored region, once.
  Future<List<OfflineRegionRow>> regions() => _dao.allRegions();

  /// Downloads [spec] and records it.
  ///
  /// The row is written before the download starts so a region interrupted by
  /// a crash is still visible and can be deleted; its size stays 0 until the
  /// download finishes.
  Future<OfflineRegionRow> download(
    OfflineRegionSpec spec, {
    void Function(OfflineDownloadProgress progress)? onProgress,
  }) async {
    final id = _idFactory();
    await _dao.upsertRegion(
      OfflineRegionsCompanion.insert(
        id: id,
        name: spec.name,
        bboxMinLat: spec.bounds.south,
        bboxMinLon: spec.bounds.west,
        bboxMaxLat: spec.bounds.north,
        bboxMaxLon: spec.bounds.east,
        sizeBytes: 0,
        maplibreRegionId: const Value(null),
      ),
    );
    try {
      final result = await _api.download(spec, onProgress: onProgress);
      await _dao.setDownloadResult(
        id,
        maplibreRegionId: result.maplibreRegionId,
        sizeBytes: result.sizeBytes,
        downloadedAt: _clock().toUtc(),
      );
    } on Object {
      await _dao.deleteRegion(id);
      rethrow;
    }
    final row = await _dao.regionById(id);
    if (row == null) {
      throw OfflineDownloadException(
        'Region $id disappeared while downloading',
      );
    }
    return row;
  }

  /// Downloads the area of [id] again with [styleUrl] and swaps the tiles
  /// underneath the same row, so the area never disappears from the list.
  /// The old tiles go only once the new ones are complete; a failed refresh
  /// leaves the area as it was.
  Future<OfflineRegionRow> refresh(
    String id, {
    required String styleUrl,
    void Function(OfflineDownloadProgress progress)? onProgress,
  }) async {
    final row = await _dao.regionById(id);
    if (row == null) {
      throw OfflineDownloadException('Region $id is not on this device');
    }
    final spec = OfflineRegionSpec(
      name: row.name,
      bounds: BoundingBox(
        south: row.bboxMinLat,
        west: row.bboxMinLon,
        north: row.bboxMaxLat,
        east: row.bboxMaxLon,
      ),
      styleUrl: styleUrl,
    );
    final result = await _api.download(spec, onProgress: onProgress);
    final previous = row.maplibreRegionId;
    if (previous != null) await _api.delete(previous);
    await _dao.setDownloadResult(
      id,
      maplibreRegionId: result.maplibreRegionId,
      sizeBytes: result.sizeBytes,
      downloadedAt: _clock().toUtc(),
    );
    return (await _dao.regionById(id))!;
  }

  /// Deletes the tiles and the row.
  Future<void> delete(String id) async {
    final row = await _dao.regionById(id);
    if (row == null) return;
    final regionId = row.maplibreRegionId;
    if (regionId != null) {
      await _api.delete(regionId);
    }
    await _dao.deleteRegion(id);
  }

  /// Drops rows whose MapLibre pack is gone, e.g. after the offline database
  /// was reset by the OS or by a reinstall.
  Future<void> reconcile() async {
    final live = (await _api.regionIds()).toSet();
    for (final row in await _dao.allRegions()) {
      final regionId = row.maplibreRegionId;
      if (regionId != null && !live.contains(regionId)) {
        await _dao.deleteRegion(row.id);
      }
    }
  }
}

@Riverpod(keepAlive: true)
OfflineMapApi offlineMapApi(Ref ref) => const MaplibreOfflineMapApi();

@Riverpod(keepAlive: true)
OfflineRegionsRepository offlineRegionsRepository(Ref ref) =>
    OfflineRegionsRepository(
      dao: ref.watch(offlineRegionsDaoProvider),
      api: ref.watch(offlineMapApiProvider),
    );

/// Every stored region, as rows change.
///
/// Written by hand rather than generated: riverpod_generator cannot emit a
/// return type whose class lives in another library's `part` file, which is
/// where drift puts [OfflineRegionRow].
final offlineRegionsProvider =
    StreamProvider.autoDispose<List<OfflineRegionRow>>(
      (ref) => ref.watch(offlineRegionsRepositoryProvider).watchRegions(),
    );

/// Progress of the download currently running, if any.
///
/// One at a time: MapLibre shares a tile budget across regions, and two
/// concurrent downloads make both progress bars meaningless.
@Riverpod(keepAlive: true)
class OfflineDownloadController extends _$OfflineDownloadController {
  @override
  OfflineDownloadProgress? build() => null;

  /// Whether a download is running right now.
  bool get isDownloading => state != null;

  /// Downloads the area described by [spec], updating [state] as it goes.
  Future<void> download(OfflineRegionSpec spec) async {
    if (state != null) return;
    state = const OfflineDownloadProgress(fraction: 0, completedBytes: 0);
    try {
      await ref
          .read(offlineRegionsRepositoryProvider)
          .download(spec, onProgress: (p) => state = p);
    } finally {
      state = null;
    }
  }

  /// Fetches the area [id] again with the map's current style.
  Future<void> refresh(String id) async {
    if (state != null) return;
    state = const OfflineDownloadProgress(fraction: 0, completedBytes: 0);
    try {
      await ref
          .read(offlineRegionsRepositoryProvider)
          .refresh(
            id,
            styleUrl: ref.read(offlineStyleUrlProvider),
            onProgress: (p) => state = p,
          );
    } finally {
      state = null;
    }
  }
}

/// The style URL a download should capture: whatever the map is showing.
@Riverpod(keepAlive: true)
String offlineStyleUrl(Ref ref) =>
    ref.watch(effectiveConfigProvider).mapStyleUrl;
