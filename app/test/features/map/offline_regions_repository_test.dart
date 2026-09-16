import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/daos/offline_regions_dao.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/offline_fakes.dart';

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
      clock: () => DateTime.utc(2026, 9, 15, 12),
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

  test('regions lists what is stored, in name order', () async {
    await repository.download(spec);
    await repository.download(
      const OfflineRegionSpec(
        name: 'Aargau',
        bounds: bounds,
        styleUrl: 'https://tiles.example/style.json',
      ),
    );

    expect((await repository.regions()).map((r) => r.name), [
      'Aargau',
      'Zurich',
    ]);
  });

  test('progress carries the bytes written so far', () async {
    api.progressEvents = const [
      OfflineDownloadProgress(fraction: 0.25, completedBytes: 256),
      OfflineDownloadProgress(fraction: 0.75, completedBytes: 768),
    ];
    final seen = <OfflineDownloadProgress>[];

    await repository.download(spec, onProgress: seen.add);

    expect(seen.map((p) => p.completedBytes), [256, 768]);
  });

  test('the log descriptions name the region, the share and the cause', () {
    expect(spec.toString(), startsWith('OfflineRegionSpec(Zurich, '));
    expect(
      spec.toString(),
      endsWith('z6.0-15.0, https://tiles.example/style.json)'),
    );
    expect(
      const OfflineDownloadProgress(
        fraction: 0.756,
        completedBytes: 768,
      ).toString(),
      'OfflineDownloadProgress(76%, 768 B)',
    );
    expect(
      OfflineDownloadException('no space left').toString(),
      'OfflineDownloadException: no space left',
    );
  });

  test('a download that fails unexpectedly leaves no row behind', () async {
    // Not an OfflineDownloadException: whatever the manager throws, the
    // half-written row has to go and the caller has to hear about it.
    api.failWith = StateError('offline database is locked');

    await expectLater(repository.download(spec), throwsA(isA<StateError>()));
    expect(await dao.allRegions(), isEmpty);
  });

  test(
    'a region deleted while it downloads is reported, not returned',
    () async {
      api.duringDownload = () => dao.deleteRegion('region-0');

      await expectLater(
        repository.download(spec),
        throwsA(
          isA<OfflineDownloadException>().having(
            (e) => e.message,
            'message',
            contains('disappeared'),
          ),
        ),
      );
    },
  );

  test('a manager that refuses to delete keeps the row', () async {
    final row = await repository.download(spec);
    api.deleteFailWith = OfflineDownloadException('offline database is busy');

    await expectLater(
      repository.delete(row.id),
      throwsA(isA<OfflineDownloadException>()),
    );

    // The tiles are still on the device, so the row that offers to delete
    // them again must stay.
    expect((await dao.allRegions()).map((r) => r.id), [row.id]);
  });

  test('reconcile keeps a row whose download never finished', () async {
    // A crash between writing the row and MapLibre handing an id back.
    await dao.upsertRegion(
      OfflineRegionsCompanion.insert(
        id: 'interrupted',
        name: 'Half a region',
        bboxMinLat: bounds.south,
        bboxMinLon: bounds.west,
        bboxMaxLat: bounds.north,
        bboxMaxLon: bounds.east,
        sizeBytes: 0,
        maplibreRegionId: const Value(null),
      ),
    );

    await repository.reconcile();

    expect((await dao.allRegions()).map((r) => r.id), ['interrupted']);
  });

  test('reconcile drops nothing when the manager cannot be asked', () async {
    final row = await repository.download(spec);
    api.regionIdsFailWith = StateError('offline manager unavailable');

    await expectLater(repository.reconcile(), throwsA(isA<StateError>()));
    expect((await dao.allRegions()).map((r) => r.id), [row.id]);
  });

  group('the download controller', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          offlineRegionsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
    });

    test(
      'publishes progress while the download runs and clears it after',
      () async {
        api.progressEvents = const [
          OfflineDownloadProgress(fraction: 0.5, completedBytes: 512),
        ];
        final midFlight = <double?>[];
        api.duringDownload = () async => midFlight.add(
          container.read(offlineDownloadControllerProvider)?.fraction,
        );
        final controller = container.read(
          offlineDownloadControllerProvider.notifier,
        );
        expect(controller.isDownloading, isFalse);

        await controller.download(spec);

        expect(midFlight, [0.5]);
        expect(container.read(offlineDownloadControllerProvider), isNull);
        expect(controller.isDownloading, isFalse);
      },
    );

    test('a second download is ignored while one is running', () async {
      final held = Completer<void>();
      api.duringDownload = () => held.future;
      final controller = container.read(
        offlineDownloadControllerProvider.notifier,
      );

      final running = controller.download(spec);
      await controller.download(
        const OfflineRegionSpec(
          name: 'Aargau',
          bounds: bounds,
          styleUrl: 'https://tiles.example/style.json',
        ),
      );
      held.complete();
      await running;

      // MapLibre shares a tile budget across regions, so the second request
      // is dropped rather than queued.
      expect(api.downloads.map((s) => s.name), ['Zurich']);
    });

    test(
      'a failed download clears the progress and reports the failure',
      () async {
        api.failWith = OfflineDownloadException('no space left');
        final controller = container.read(
          offlineDownloadControllerProvider.notifier,
        );

        await expectLater(
          controller.download(spec),
          throwsA(isA<OfflineDownloadException>()),
        );

        expect(container.read(offlineDownloadControllerProvider), isNull);
        expect(controller.isDownloading, isFalse);
      },
    );
  });

  test('the download style URL follows the map style in use', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appConfigProvider.overrideWithValue(
          const AppConfig(mapStyleUrl: 'https://tiles.example/style.json'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(offlineStyleUrlProvider),
      'https://tiles.example/style.json',
    );
  });

  group('refresh', () {
    test('a download records when it happened', () async {
      final row = await repository.download(spec);

      expect(row.downloadedAt, DateTime.utc(2026, 9, 15, 12));
    });

    test('is due after eight weeks, or when the date is unknown', () {
      final now = DateTime.utc(2026, 9, 15);
      OfflineRegionRow at(DateTime? downloadedAt) => OfflineRegionRow(
        id: 'r',
        name: 'r',
        bboxMinLat: 0,
        bboxMinLon: 0,
        bboxMaxLat: 1,
        bboxMaxLon: 1,
        maplibreRegionId: 1,
        sizeBytes: 1,
        downloadedAt: downloadedAt,
      );

      expect(OfflineRegionsRepository.isRefreshDue(at(null), now), isTrue);
      expect(
        OfflineRegionsRepository.isRefreshDue(
          at(DateTime.utc(2026, 9, 1)),
          now,
        ),
        isFalse,
      );
      expect(
        OfflineRegionsRepository.isRefreshDue(
          at(DateTime.utc(2026, 7, 20)),
          now,
        ),
        isTrue,
      );
    });

    test('downloads the same bounds again and swaps the tiles under the '
        'row', () async {
      final old = await repository.download(spec);
      api.resultSizeBytes = 2048;

      final fresh = await repository.refresh(
        old.id,
        styleUrl: 'https://tiles.example/style2.json',
      );

      expect(api.downloads, hasLength(2));
      expect(api.downloads.last.bounds, bounds);
      expect(api.downloads.last.name, 'Zurich');
      expect(api.downloads.last.styleUrl, 'https://tiles.example/style2.json');
      expect(api.deleted, [old.maplibreRegionId]);
      expect(fresh.id, old.id);
      expect(fresh.maplibreRegionId, isNot(old.maplibreRegionId));
      expect(fresh.sizeBytes, 2048);
      expect(await repository.regions(), hasLength(1));
    });

    test('a failed refresh leaves the area as it was', () async {
      final old = await repository.download(spec);
      api.failWith = OfflineDownloadException('no signal');

      await expectLater(
        repository.refresh(old.id, styleUrl: spec.styleUrl),
        throwsA(isA<OfflineDownloadException>()),
      );

      expect(api.deleted, isEmpty);
      final rows = await repository.regions();
      expect(rows.single.maplibreRegionId, old.maplibreRegionId);
      expect(rows.single.sizeBytes, old.sizeBytes);
    });
  });
}
