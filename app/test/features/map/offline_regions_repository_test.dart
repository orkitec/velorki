import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/daos/offline_regions_dao.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A stand-in for MapLibre's offline manager. The real one is a set of
/// top-level method channel calls, which a unit test cannot serve.
class FakeOfflineMapApi implements OfflineMapApi {
  final List<OfflineRegionSpec> downloads = <OfflineRegionSpec>[];
  final List<int> deleted = <int>[];
  final List<int> live = <int>[];

  /// Progress events every download reports before finishing.
  List<OfflineDownloadProgress> progressEvents = const [];

  /// Thrown instead of finishing, when set.
  Object? failWith;

  int nextRegionId = 1;
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
    deleted.add(maplibreRegionId);
    live.remove(maplibreRegionId);
  }

  @override
  Future<List<int>> regionIds() async => List<int>.of(live);
}

void main() {
  late VelorkiDatabase db;
  late OfflineRegionsDao dao;
  late FakeOfflineMapApi api;
  late OfflineRegionsRepository repository;
  var nextId = 0;

  const bounds = BoundingBox(south: 47.0, west: 8.0, north: 47.5, east: 8.6);
  const spec = OfflineRegionSpec(
    name: 'Zurich',
    bounds: bounds,
    styleUrl: 'https://tiles.example/style.json',
  );

  setUp(() {
    db = VelorkiDatabase.memory();
    dao = OfflineRegionsDao(db);
    api = FakeOfflineMapApi();
    nextId = 0;
    repository = OfflineRegionsRepository(
      dao: dao,
      api: api,
      idFactory: () => 'region-${nextId++}',
    );
  });

  tearDown(() => db.close());

  test('the default zoom range is the one the plan calls for', () {
    expect(offlineMinZoom, 6);
    expect(offlineMaxZoom, 15);
    expect(spec.minZoom, offlineMinZoom);
    expect(spec.maxZoom, offlineMaxZoom);
  });

  test('a download stores the bounds, the region id and the size', () async {
    api.resultSizeBytes = 4096;

    final row = await repository.download(spec);

    expect(api.downloads.single.bounds, bounds);
    expect(api.downloads.single.styleUrl, 'https://tiles.example/style.json');
    expect(row.id, 'region-0');
    expect(row.name, 'Zurich');
    expect(row.bboxMinLat, 47.0);
    expect(row.bboxMinLon, 8.0);
    expect(row.bboxMaxLat, 47.5);
    expect(row.bboxMaxLon, 8.6);
    expect(row.maplibreRegionId, 1);
    expect(row.sizeBytes, 4096);
  });

  test('progress is reported to the caller', () async {
    api.progressEvents = const [
      OfflineDownloadProgress(fraction: 0.5, completedBytes: 512),
      OfflineDownloadProgress(fraction: 1, completedBytes: 1024),
    ];
    final seen = <double>[];

    await repository.download(spec, onProgress: (p) => seen.add(p.fraction));

    expect(seen, [0.5, 1]);
  });

  test('the row exists while the download runs', () async {
    api.progressEvents = const [
      OfflineDownloadProgress(fraction: 0.5, completedBytes: 512),
    ];
    final midFlight = Completer<List<OfflineRegionRow>>();

    await repository.download(
      spec,
      onProgress: (_) {
        if (!midFlight.isCompleted) {
          unawaited(dao.allRegions().then(midFlight.complete));
        }
      },
    );
    final rows = await midFlight.future;

    // Written before the download starts, so an interrupted download is still
    // visible and can be deleted; the size is only known at the end.
    expect(rows, hasLength(1));
    expect(rows.single.maplibreRegionId, isNull);
    expect(rows.single.sizeBytes, 0);
  });

  test('a failed download leaves no row behind', () async {
    api.failWith = OfflineDownloadException('no space left');

    await expectLater(
      repository.download(spec),
      throwsA(isA<OfflineDownloadException>()),
    );
    expect(await dao.allRegions(), isEmpty);
  });

  test('delete removes the MapLibre pack and the row', () async {
    final row = await repository.download(spec);

    await repository.delete(row.id);

    expect(api.deleted, [1]);
    expect(await dao.allRegions(), isEmpty);
  });

  test('deleting an unknown id is a no-op', () async {
    await repository.delete('nope');

    expect(api.deleted, isEmpty);
  });

  test('watchRegions emits the stored regions in name order', () async {
    await repository.download(spec);
    await repository.download(
      const OfflineRegionSpec(
        name: 'Aargau',
        bounds: bounds,
        styleUrl: 'https://tiles.example/style.json',
      ),
    );

    expect(
      await repository.watchRegions().first,
      isA<List<OfflineRegionRow>>().having(
        (rows) => rows.map((r) => r.name).toList(),
        'names',
        ['Aargau', 'Zurich'],
      ),
    );
  });

  test('reconcile drops rows whose MapLibre pack is gone', () async {
    final kept = await repository.download(spec);
    final orphaned = await repository.download(
      const OfflineRegionSpec(
        name: 'Gone',
        bounds: bounds,
        styleUrl: 'https://tiles.example/style.json',
      ),
    );
    // Simulate the offline database being reset behind our back.
    api.live.remove(orphaned.maplibreRegionId);

    await repository.reconcile();

    expect((await dao.allRegions()).map((r) => r.id), [kept.id]);
  });
}
