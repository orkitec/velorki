import 'package:velorki/features/map/data/offline_regions_repository.dart';

/// A stand-in for MapLibre's offline manager. The real one is a set of
/// top-level method channel calls, which a unit test cannot serve.
class FakeOfflineMapApi implements OfflineMapApi {
  /// Every spec handed to [download], in order.
  final List<OfflineRegionSpec> downloads = <OfflineRegionSpec>[];

  /// Every id handed to [delete], in order.
  final List<int> deleted = <int>[];

  /// The ids [regionIds] answers with, i.e. the packs MapLibre still holds.
  final List<int> live = <int>[];

  /// Progress events every download reports before finishing.
  List<OfflineDownloadProgress> progressEvents = const [];

  /// Thrown instead of finishing, when set.
  Object? failWith;

  /// Thrown by [delete] instead of removing anything, when set.
  Object? deleteFailWith;

  /// Thrown by [regionIds] instead of answering, when set.
  Object? regionIdsFailWith;

  /// Awaited inside [download], after the progress events and before the
  /// result: the hook a test uses to hold a download open, or to change the
  /// world while one is running.
  Future<void> Function()? duringDownload;

  /// The MapLibre id the next download is given.
  int nextRegionId = 1;

  /// The size every finished download reports.
  int resultSizeBytes = 1024;

  @override
  Future<OfflineDownloadResult> download(
    OfflineRegionSpec spec, {
    void Function(OfflineDownloadProgress progress)? onProgress,
  }) async {
    downloads.add(spec);
    for (final event in progressEvents) {
      onProgress?.call(event);
    }
    await duringDownload?.call();
    final failure = failWith;
    if (failure != null) throw failure;
    final id = nextRegionId++;
    live.add(id);
    return OfflineDownloadResult(
      maplibreRegionId: id,
      sizeBytes: resultSizeBytes,
    );
  }

  @override
  Future<void> delete(int maplibreRegionId) async {
    final failure = deleteFailWith;
    if (failure != null) throw failure;
    deleted.add(maplibreRegionId);
    live.remove(maplibreRegionId);
  }

  @override
  Future<List<int>> regionIds() async {
    final failure = regionIdsFailWith;
    if (failure != null) throw failure;
    return List<int>.of(live);
  }
}
