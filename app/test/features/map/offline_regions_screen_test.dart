import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/db/daos/offline_regions_dao.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki/features/map/presentation/offline_regions_screen.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/offline_fakes.dart';

const String _styleUrl = 'https://tiles.example/style.json';
const BoundingBox _visible = BoundingBox(
  south: 47.0,
  west: 8.0,
  north: 47.5,
  east: 8.6,
);

/// Everything the offline maps screen needs: an in-memory database and a
/// stand-in for MapLibre's offline manager.
class OfflineHarness {
  /// Wires the fakes together.
  OfflineHarness() : db = VelorkiDatabase.memory();

  /// The in-memory database behind the region table.
  final VelorkiDatabase db;

  /// The offline manager the repository talks to.
  final FakeOfflineMapApi api = FakeOfflineMapApi();

  /// The table the screen lists.
  OfflineRegionsDao get dao => db.offlineRegionsDao;

  /// Writes a region straight into the table, as a finished download would.
  Future<void> seedRegion({
    required String id,
    required String name,
    required int sizeBytes,
    int? maplibreRegionId,
  }) {
    if (maplibreRegionId != null) api.live.add(maplibreRegionId);
    return dao.upsertRegion(
      OfflineRegionsCompanion.insert(
        id: id,
        name: name,
        bboxMinLat: _visible.south,
        bboxMinLon: _visible.west,
        bboxMaxLat: _visible.north,
        bboxMaxLon: _visible.east,
        sizeBytes: sizeBytes,
        maplibreRegionId: Value(maplibreRegionId),
      ),
    );
  }
}

/// Pumps the screen with the fakes in place.
///
/// [map] stands in for a live map: without one the screen has no bounds to
/// download and says so.
Future<OfflineHarness> pumpOfflineRegions(
  WidgetTester tester, {
  OfflineHarness? harness,
  FakeMapController? map,
  bool cyclosmOverlay = false,
  List<Override> extraOverrides = const <Override>[],
}) async {
  final h = harness ?? OfflineHarness();
  addTearDown(h.db.close);
  await tester.binding.setSurfaceSize(const Size(1000, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues(<String, Object>{
    if (cyclosmOverlay) 'map.cyclosm_overlay': true,
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        velorkiDatabaseProvider.overrideWithValue(h.db),
        appConfigProvider.overrideWithValue(
          const AppConfig(mapStyleUrl: _styleUrl),
        ),
        offlineMapApiProvider.overrideWithValue(h.api),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: OfflineRegionsScreen(mapController: map),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

/// A map showing [_visible], which is what the screen offers to download.
FakeMapController _mapAt() => FakeMapController()..visibleBounds = _visible;

/// Advances the download without waiting for the screen to settle.
///
/// A download that has not reported progress yet shows an indeterminate
/// progress bar, and `pumpAndSettle` never returns while that spins.
Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The download button, whichever label it currently carries.
FilledButton _downloadButton(WidgetTester tester) =>
    tester.widget<FilledButton>(
      find.ancestor(
        of: find.byIcon(Icons.download_outlined),
        matching: find.byType(FilledButton),
      ),
    );

/// Unmounts the tree and lets drift's zero-duration teardown timer fire.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('without a downloaded area the screen explains what to do', (
    tester,
  ) async {
    await pumpOfflineRegions(tester);

    expect(find.text('Offline maps'), findsOneWidget);
    expect(find.textContaining('No offline areas yet.'), findsOneWidget);
    expect(
      find.textContaining('Open this screen from the map'),
      findsOneWidget,
    );
    expect(find.text('Download visible area'), findsOneWidget);
    expect(_downloadButton(tester).onPressed, isNull);
    await _unmount(tester);
  });

  testWidgets('downloaded areas are listed with their name and size', (
    tester,
  ) async {
    final h = OfflineHarness();
    await h.seedRegion(
      id: 'a',
      name: 'Zurich',
      sizeBytes: 5 * 1024 * 1024,
      maplibreRegionId: 1,
    );
    await h.seedRegion(id: 'b', name: 'Aargau', sizeBytes: 4096);
    await pumpOfflineRegions(tester, harness: h);

    // Alphabetical, as the table hands them over.
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(names, ['Aargau', 'Zurich']);
    expect(find.text('4.0 kB'), findsOneWidget);
    expect(find.text('5.0 MB'), findsOneWidget);
    expect(find.textContaining('No offline areas yet.'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a size is only shown once the download reported one', (
    tester,
  ) async {
    final h = OfflineHarness();
    await h.seedRegion(id: 'a', name: 'Interrupted', sizeBytes: 0);
    await pumpOfflineRegions(tester, harness: h);

    expect(find.text('—'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the visible area is downloaded and its progress is shown', (
    tester,
  ) async {
    final h = OfflineHarness();
    h.api.progressEvents = const [
      OfflineDownloadProgress(fraction: 0.4, completedBytes: 2048),
    ];
    h.api.resultSizeBytes = 4096;
    final held = Completer<void>();
    h.api.duringDownload = () => held.future;
    await pumpOfflineRegions(tester, harness: h, map: _mapAt());
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('Download visible area'));
    await _tick(tester);

    expect(find.text('Downloading…'), findsOneWidget);
    expect(_downloadButton(tester).onPressed, isNull);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(0.4, 1e-9),
    );
    // The screen names the area after the ones already stored and downloads
    // the style the map is showing.
    expect(h.api.downloads.single.name, 'Map area 1');
    expect(h.api.downloads.single.bounds, _visible);
    expect(h.api.downloads.single.styleUrl, _styleUrl);

    held.complete();
    await _tick(tester);

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Map area 1'), findsOneWidget);
    expect(find.text('4.0 kB'), findsOneWidget);
    expect(find.text('Download visible area'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('deleting an area asks first, then removes it', (tester) async {
    final h = OfflineHarness();
    await h.seedRegion(
      id: 'a',
      name: 'Zurich',
      sizeBytes: 4096,
      maplibreRegionId: 7,
    );
    await pumpOfflineRegions(tester, harness: h);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete offline area?'), findsOneWidget);
    expect(
      find.text('The downloaded tiles are removed from this device.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(h.api.deleted, [7]);
    expect(await h.dao.allRegions(), isEmpty);
    expect(find.text('Zurich'), findsNothing);
    expect(find.textContaining('No offline areas yet.'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('cancelling the confirmation keeps the area', (tester) async {
    final h = OfflineHarness();
    await h.seedRegion(
      id: 'a',
      name: 'Zurich',
      sizeBytes: 4096,
      maplibreRegionId: 7,
    );
    await pumpOfflineRegions(tester, harness: h);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(h.api.deleted, isEmpty);
    expect(find.text('Zurich'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a failed download is reported and stores nothing', (
    tester,
  ) async {
    final h = OfflineHarness();
    h.api.failWith = OfflineDownloadException('no space left on device');
    await pumpOfflineRegions(tester, harness: h, map: _mapAt());

    await tester.tap(find.text('Download visible area'));
    await _tick(tester);

    expect(find.textContaining('Download failed.'), findsOneWidget);
    expect(find.textContaining('no space left on device'), findsOneWidget);
    expect(await h.dao.allRegions(), isEmpty);
    expect(find.textContaining('No offline areas yet.'), findsOneWidget);
    expect(_downloadButton(tester).onPressed, isNotNull);
    await _unmount(tester);
  });

  testWidgets('a table that cannot be read is reported in place of the list', (
    tester,
  ) async {
    await pumpOfflineRegions(
      tester,
      extraOverrides: <Override>[
        offlineRegionsProvider.overrideWith(
          (ref) => Stream<List<OfflineRegionRow>>.error(
            StateError('offline database is unreadable'),
          ),
        ),
      ],
    );

    expect(
      find.textContaining('offline database is unreadable'),
      findsOneWidget,
    );
    expect(find.textContaining('No offline areas yet.'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('the CyclOSM overlay blocks the download and says why', (
    tester,
  ) async {
    await pumpOfflineRegions(tester, map: _mapAt(), cyclosmOverlay: true);

    expect(
      find.textContaining('tile policy forbids bulk downloading'),
      findsOneWidget,
    );
    expect(_downloadButton(tester).onPressed, isNull);
    await _unmount(tester);
  });
}
