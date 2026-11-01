import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/platform_features.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/offline/presentation/area_update_chip.dart';
import 'package:velorki/features/routing_tiles/application/tile_download_controller.dart';
import 'package:velorki/features/routing_tiles/data/tile_downloader.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../map/support/offline_fakes.dart';
import '../routing_tiles/support/fake_segments.dart';

final Uint8List _body = Uint8List.fromList(utf8.encode('rd5-body'));

const TileName _tyrol = TileName(10, 45);
const TileName _east = TileName(15, 45);

/// Inside E10_N45.
const BoundingBox _overTyrol = BoundingBox(
  south: 46,
  west: 10.5,
  north: 47,
  east: 11.5,
);

/// Across E10_N45 and E15_N45.
const BoundingBox _acrossBoth = BoundingBox(
  south: 46,
  west: 14.5,
  north: 47,
  east: 15.5,
);

/// Somewhere with nothing downloaded.
const BoundingBox _overSpain = BoundingBox(
  south: 40,
  west: -4,
  north: 41,
  east: -3,
);

Map<String, Object?> _manifest() => <String, Object?>{
  'formatVersion': '11.2',
  'tiles': <Object?>[
    for (final tile in <TileName>[_tyrol, _east])
      <String, Object?>{
        'tile': tile.name,
        'bytes': _body.length,
        'updatedAt': '2026-10-12T01:03:00Z',
      },
  ],
};

class _Harness {
  _Harness()
    : adapter = FakeSegmentsAdapter((options) {
        if (options.uri.path.endsWith('manifest.json')) {
          return FakeSegmentsResponse.json(_manifest());
        }
        return FakeSegmentsResponse.bytes(_body);
      }),
      db = VelorkiDatabase.memory(),
      storage = BrouterStorage(tempDir('velorki-visible-area')) {
    storage.segments.createSync(recursive: true);
    storage.gazetteer.createSync(recursive: true);
    storage.profiles.createSync(recursive: true);
  }

  final VelorkiDatabase db;
  final BrouterStorage storage;
  final FakeOfflineMapApi api = FakeOfflineMapApi();
  final FakeSegmentsAdapter adapter;

  /// A tile on the device with its gazetteer, built [updatedAt].
  Future<void> seedTile(
    TileName tile, {
    DateTime? updatedAt,
    RoutingTileState state = RoutingTileState.ready,
  }) async {
    File('${storage.segments.path}/${tile.fileName}').writeAsBytesSync(_body);
    File('${storage.gazetteer.path}/${tile.gazetteerFileName}')
        .writeAsStringSync('gaz');
    await db.routingTilesDao.markReady(
      tile.name,
      bytes: _body.length,
      updatedAt: updatedAt ?? DateTime.utc(2026, 10, 12, 1, 3),
      formatVersion: '11.2',
    );
    if (state != RoutingTileState.ready) {
      await db.routingTilesDao.setState(tile.name, state);
    }
  }

  /// A finished map area over [box].
  Future<void> seedRegion(BoundingBox box) async {
    await db.offlineRegionsDao.upsertRegion(
      OfflineRegionsCompanion.insert(
        id: 'area',
        name: 'Area',
        bboxMinLat: box.south,
        bboxMinLon: box.west,
        bboxMaxLat: box.north,
        bboxMaxLon: box.east,
        sizeBytes: 0,
        maplibreRegionId: const Value(null),
      ),
    );
    await db.offlineRegionsDao.setDownloadResult(
      'area',
      maplibreRegionId: 7,
      sizeBytes: 1024,
      downloadedAt: DateTime.now().toUtc(),
    );
  }

  List<Override> get overrides => <Override>[
    velorkiDatabaseProvider.overrideWithValue(db),
    appConfigProvider.overrideWithValue(
      const AppConfig(segmentsUrl: 'https://mirror.test/segments4'),
    ),
    brouterStorageProvider.overrideWith((ref) async => storage),
    brouterProfilesProvider.overrideWith((ref) async => storage.profiles),
    segmentsDioProvider.overrideWithValue(segmentsDioWith(adapter)),
    offlineMapApiProvider.overrideWithValue(api),
  ];
}

/// Real I/O (the files, the in-memory database) needs real time to land.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

Future<(_Harness, FakeMapController)> _pump(
  WidgetTester tester, {
  BoundingBox bounds = _overTyrol,
  PlatformFeatures features = PlatformFeatures.browser,
  Future<void> Function(_Harness harness)? seed,
  List<Override> extraOverrides = const <Override>[],
}) async {
  final h = _Harness();
  addTearDown(h.db.close);
  await seed?.call(h);
  await tester.binding.setSurfaceSize(const Size(1080, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // A tall screen: a short one gets the compact column, without the button.
  tester.view.physicalSize = const Size(3240, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final map = FakeMapController()..visibleBounds = bounds;
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformFeaturesProvider.overrideWithValue(features),
        ...h.overrides,
        ...extraOverrides,
      ],
      child: testApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Align(
                alignment: Alignment.topRight,
                child: MapControls(controller: map),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: AreaUpdateChip(controller: map),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (h, map);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Finder get _downloaded => find.byTooltip(l10n.offlineAreaDownloaded);
Finder get _toDownload => find.byTooltip(l10n.offlineEntryTitle);
Finder get _updates => find.byTooltip(l10n.offlineAreaUpdates);
Finder get _updateChip => find.text(l10n.mapAreaUpdateAvailable);

/// A queue that is mid-download of the tile under the view, until cancelled.
class _RunningQueue extends TileDownloadQueue {
  @override
  TileDownloadQueueState build() => TileDownloadQueueState(
    current: _tyrol,
    progress: TileDownloadProgress(tile: _tyrol, received: 1, total: 4),
  );

  @override
  void cancel() => state = const TileDownloadQueueState();
}

void main() {
  testWidgets('a view with nothing on the device opens the download', (
    tester,
  ) async {
    await _pump(tester);

    expect(_toDownload, findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline), findsNothing);

    await tester.tap(_toDownload);
    await tester.pumpAndSettle();
    expect(find.text(l10n.offlineTitle), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a downloaded view shows so, in the accent, and a tap says so '
      'with the way to the offline data', (tester) async {
    await _pump(tester, seed: (h) => h.seedTile(_tyrol));

    expect(_downloaded, findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.download_for_offline));
    expect(icon, isNotNull);
    final button = tester.widget<IconButton>(
      find.ancestor(of: _downloaded, matching: find.byType(IconButton)),
    );
    final context = tester.element(_downloaded);
    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{}),
      Theme.of(context).velorki.accent,
    );

    await tester.tap(_downloaded);
    await tester.pumpAndSettle();
    expect(find.text(l10n.offlineAreaDownloaded), findsOneWidget);
    // No download dialog, no screen: the rider is only told.
    expect(find.text(l10n.offlineTitle), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text(l10n.offlineManage));
    await tester.pumpAndSettle();
    expect(find.text(l10n.offlineTitle), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a view partly downloaded offers the rest', (tester) async {
    await _pump(tester, bounds: _acrossBoth, seed: (h) => h.seedTile(_tyrol));

    expect(_toDownload, findsOneWidget);
    await tester.tap(_toDownload);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.offlineDownloadVisible));
    await _settle(tester);
    // The dialog lists what is missing, and only that.
    expect(find.textContaining('${_east.name} ·'), findsOneWidget);
    expect(find.textContaining('${_tyrol.name} ·'), findsNothing);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    await _unmount(tester);
  });

  testWidgets('the state follows the camera', (tester) async {
    final (_, map) = await _pump(
      tester,
      bounds: _overSpain,
      seed: (h) => h.seedTile(_tyrol),
    );
    expect(_toDownload, findsOneWidget);

    map.visibleBounds = _overTyrol;
    map.emitCameraIdle();
    await tester.pump();
    expect(_downloaded, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the button of a view with an update opens the offline page', (
    tester,
  ) async {
    await _pump(
      tester,
      seed: (h) => h.seedTile(
        _tyrol,
        updatedAt: DateTime.utc(2026, 9),
        state: RoutingTileState.stale,
      ),
    );

    expect(_updates, findsOneWidget);
    expect(_downloaded, findsNothing);
    expect(find.byType(Badge), findsOneWidget);

    await tester.tap(_updates);
    await tester.pumpAndSettle();
    // The page, not an update started in place.
    expect(find.text(l10n.offlineTitle), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a tile the mirror has rebuilt is offered as an update, on '
      'the chip, in place', (tester) async {
    final (h, _) = await _pump(
      tester,
      seed: (h) => h.seedTile(
        _tyrol,
        updatedAt: DateTime.utc(2026, 9),
        state: RoutingTileState.stale,
      ),
    );

    expect(_updateChip, findsOneWidget);
    expect(find.text(l10n.mapAreaUpdate), findsOneWidget);
    expect(find.text(l10n.mapStopsDownload), findsNothing);

    await tester.tap(_updateChip);
    await _settle(tester);
    // The tiles screen's own update confirmation, for this tile.
    expect(find.text(l10n.routingTilesTitle), findsOneWidget);
    expect(find.textContaining('${_tyrol.name} ·'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await _settle(tester);
    for (var i = 0; i < 20 && _downloaded.evaluate().isEmpty; i++) {
      await _settle(tester);
    }
    expect(_downloaded, findsOneWidget);
    expect(_updateChip, findsNothing);
    expect(h.adapter.requests.where((r) => r.uri.path.endsWith('.rd5')), [
      isNotNull,
    ]);
    await _unmount(tester);
  });

  testWidgets('the update chip is not there for a view that needs a '
      'download, or has nothing to update', (tester) async {
    await _pump(tester);
    expect(_toDownload, findsOneWidget);
    expect(_updateChip, findsNothing);
    await _unmount(tester);

    await _pump(tester, seed: (h) => h.seedTile(_tyrol));
    expect(_downloaded, findsOneWidget);
    expect(_updateChip, findsNothing);
    await _unmount(tester);
  });

  testWidgets('the update chip follows the camera', (tester) async {
    final (_, map) = await _pump(
      tester,
      bounds: _overSpain,
      seed: (h) => h.seedTile(_tyrol, state: RoutingTileState.stale),
    );
    expect(_updateChip, findsNothing);

    map.visibleBounds = _overTyrol;
    map.emitCameraIdle();
    await tester.pump();
    expect(_updateChip, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('closing the update chip hides it over that area', (
    tester,
  ) async {
    final (_, map) = await _pump(
      tester,
      seed: (h) => h.seedTile(_tyrol, state: RoutingTileState.stale),
    );
    expect(_updateChip, findsOneWidget);

    await tester.tap(find.byTooltip(l10n.mapAreaHintHide));
    await tester.pump();
    expect(_updateChip, findsNothing);
    // The button still says there are updates.
    expect(_updates, findsOneWidget);

    map.visibleBounds = _overSpain;
    map.emitCameraIdle();
    await tester.pump();
    map.visibleBounds = _overTyrol;
    map.emitCameraIdle();
    await tester.pump();
    expect(_updateChip, findsNothing, reason: 'for the session');
    await _unmount(tester);
  });

  testWidgets('while the update runs the chip shows it, the cancel stops it '
      'and the chip comes back', (tester) async {
    await _pump(
      tester,
      seed: (h) => h.seedTile(_tyrol, state: RoutingTileState.stale),
      extraOverrides: <Override>[
        tileDownloadQueueProvider.overrideWith(_RunningQueue.new),
      ],
    );

    expect(find.text(l10n.mapOfflineDownloading), findsOneWidget);
    expect(_updateChip, findsNothing, reason: 'it says downloading now');
    expect(find.text(l10n.mapAreaUpdate), findsNothing);
    final progress = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byType(AreaUpdateChip),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(progress.value, 0.25);

    await tester.tap(find.byTooltip(l10n.routingTilesCancelDownload));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.routingTilesCancelDownload),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.mapOfflineDownloading), findsNothing);
    expect(find.text(l10n.mapAreaUpdate), findsOneWidget);
    expect(_updateChip, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('on a phone the view also needs its map area', (tester) async {
    await _pump(
      tester,
      features: PlatformFeatures.device,
      seed: (h) => h.seedTile(_tyrol),
    );
    expect(_toDownload, findsOneWidget);
    await _unmount(tester);

    await _pump(
      tester,
      features: PlatformFeatures.device,
      seed: (h) async {
        await h.seedTile(_tyrol);
        await h.seedRegion(_overTyrol);
      },
    );
    expect(_downloaded, findsOneWidget);
    await _unmount(tester);
  });
}
