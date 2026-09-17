import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/rd5_format_support.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki/features/routing_tiles/domain/rd5_format.dart';
import 'package:velorki/features/routing_tiles/presentation/routing_tiles_screen.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import 'support/fake_segments.dart';

const TileName _tile = TileName(10, 45);
final Uint8List _body = Uint8List.fromList(
  utf8.encode(List<String>.generate(16, (i) => 'rd5-$i;').join()),
);

Map<String, Object?> _manifest() => <String, Object?>{
  'formatVersion': '11.2',
  'tiles': <Object?>[
    <String, Object?>{
      'tile': 'E10_N45',
      'bytes': _body.length,
      'updatedAt': '2026-09-12T01:03:00Z',
    },
    <String, Object?>{
      'tile': 'E5_N45',
      'bytes': 4096,
      'updatedAt': '2026-09-12T01:03:00Z',
    },
  ],
};

/// Everything the screen needs: an in-memory database, a temporary storage
/// directory and a mirror that answers from memory.
class TilesHarness {
  /// Wires the fakes together.
  TilesHarness()
    : db = VelorkiDatabase.memory(),
      storage = BrouterStorage(tempDir('velorki-screen')) {
    storage.segments.createSync(recursive: true);
    storage.profiles.createSync(recursive: true);
  }

  /// The in-memory database behind the tile table.
  final VelorkiDatabase db;

  /// The temporary `<appSupport>/brouter` stand-in.
  final BrouterStorage storage;

  /// The mirror, serving the manifest and one tile.
  final FakeSegmentsAdapter adapter = FakeSegmentsAdapter((options) {
    if (options.uri.path.endsWith('manifest.json')) {
      return FakeSegmentsResponse.json(_manifest());
    }
    return FakeSegmentsResponse.bytes(_body);
  });

  /// The overrides to hand to a `ProviderScope`.
  List<Override> get overrides => <Override>[
    velorkiDatabaseProvider.overrideWithValue(db),
    appConfigProvider.overrideWithValue(
      const AppConfig(segmentsUrl: 'https://mirror.test/segments4'),
    ),
    brouterStorageProvider.overrideWith((ref) async => storage),
    brouterProfilesProvider.overrideWith((ref) async => storage.profiles),
    segmentsDioProvider.overrideWithValue(segmentsDioWith(adapter)),
  ];

  /// Where [tile] ends up on disk.
  File tileFile(TileName tile) =>
      File('${storage.segments.path}/${tile.fileName}');
}

Future<TilesHarness> pumpTiles(
  WidgetTester tester, {
  FakeMapController? map,
  List<TileName> preselected = const <TileName>[],
  List<Override> extraOverrides = const <Override>[],
}) async {
  final harness = TilesHarness();
  addTearDown(harness.db.close);
  await tester.binding.setSurfaceSize(const Size(1080, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...harness.overrides,
        ...extraOverrides,
      ],
      child: testApp(
        home: RoutingTilesScreen(mapController: map, preselected: preselected),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return harness;
}

/// Lets the download queue run.
///
/// Writing a tile is real file I/O, and real I/O does not progress inside the
/// fake-async zone a widget test runs in; `runAsync` hands the event loop back
/// for a moment between the frames.
Future<void> runDownloads(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Unmounts the tree and lets drift's zero-duration teardown timer fire, the
/// way `test/features/planner/support/pump.dart` does.
Future<void> unmountTiles(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('without a map it explains why the area cannot be downloaded', (
    tester,
  ) async {
    await pumpTiles(tester);

    expect(find.text(l10n.routingTilesTitle), findsOneWidget);
    expect(
      find.textContaining(l10n.routingTilesSearchHint),
      findsOneWidget,
      reason: 'a downloaded region brings the offline search with it',
    );
    expect(find.textContaining(l10n.routingTilesEmpty), findsOneWidget);
    expect(find.text(l10n.routingTilesTotal(0, '')), findsOneWidget);
    expect(find.textContaining(l10n.routingTilesNeedsMap), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(l10n.routingTilesVisibleArea),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    await unmountTiles(tester);
  });

  testWidgets('the visible area is offered with its size and downloaded', (
    tester,
  ) async {
    final map = FakeMapController()
      ..visibleBounds = const BoundingBox(
        south: 46.0,
        west: 10.5,
        north: 47.0,
        east: 11.5,
      );
    final harness = await pumpTiles(tester, map: map);

    await tester.tap(find.text(l10n.routingTilesVisibleArea));
    await tester.pumpAndSettle();

    // One tile covers the whole visible box, and the manifest knows its size.
    expect(find.textContaining('E10_N45 ·'), findsOneWidget);
    expect(find.textContaining(l10n.routingTilesDataNotice), findsWidgets);
    await tester.tap(
      find.textContaining(
        l10n.routingTilesDownloadCount(1, '').split('(').first.trim(),
      ),
    );
    await tester.pump();
    await runDownloads(tester);

    expect(harness.tileFile(_tile).existsSync(), isTrue);
    expect(find.text('E10_N45'), findsOneWidget);
    expect(find.textContaining(l10n.routingTilesStateReady), findsOneWidget);
    expect(
      find.text(l10n.routingTilesTotal(1, '${_body.length} B')),
      findsOneWidget,
    );
    await unmountTiles(tester);
  });

  testWidgets('a route hands its missing tiles in and they are offered', (
    tester,
  ) async {
    await pumpTiles(tester, preselected: const <TileName>[TileName(5, 45)]);

    expect(find.text(l10n.routingTilesRouteTitle), findsOneWidget);
    expect(find.text('E5_N45'), findsOneWidget);
    expect(
      find.text(l10n.routingTilesDownloadCount(1, '4.0 kB')),
      findsOneWidget,
    );
    await unmountTiles(tester);
  });

  testWidgets('a downloaded tile can be deleted again', (tester) async {
    final map = FakeMapController()
      ..visibleBounds = const BoundingBox(
        south: 46.0,
        west: 10.5,
        north: 47.0,
        east: 11.5,
      );
    final harness = await pumpTiles(tester, map: map);
    await tester.tap(find.text(l10n.routingTilesVisibleArea));
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining(
        l10n.routingTilesDownloadCount(1, '').split('(').first.trim(),
      ),
    );
    await tester.pump();
    await runDownloads(tester);
    expect(harness.tileFile(_tile).existsSync(), isTrue);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text(l10n.routingTilesDeleteTitle('E10_N45')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonDelete));
    await tester.pump();
    await runDownloads(tester);

    expect(harness.tileFile(_tile).existsSync(), isFalse);
    expect(find.text(l10n.routingTilesTotal(0, '')), findsOneWidget);
    await unmountTiles(tester);
  });

  testWidgets('an unreachable mirror is reported with a retry', (tester) async {
    final harness = TilesHarness();
    addTearDown(harness.db.close);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          velorkiDatabaseProvider.overrideWithValue(harness.db),
          appConfigProvider.overrideWithValue(
            const AppConfig(segmentsUrl: 'https://mirror.test/segments4'),
          ),
          brouterStorageProvider.overrideWith((ref) async => harness.storage),
          brouterProfilesProvider.overrideWith(
            (ref) async => harness.storage.profiles,
          ),
          segmentsManifestServiceProvider.overrideWithValue(
            SegmentsManifestService(
              dio: segmentsDioWith(
                FakeSegmentsAdapter(
                  (_) => FakeSegmentsResponse.text('nope', status: 500),
                ),
              ),
              segmentsUrl: 'https://mirror.test/segments4',
            ),
          ),
        ],
        child: testApp(home: const RoutingTilesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(l10n.routingTilesManifestFailed('').trim()),
      findsOneWidget,
    );
    expect(find.text(l10n.assistantRetry), findsOneWidget);
    await unmountTiles(tester);
  });

  testWidgets('a tile in a newer format asks for an app update instead', (
    tester,
  ) async {
    final map = FakeMapController()
      ..visibleBounds = const BoundingBox(
        south: 46.0,
        west: 10.5,
        north: 47.0,
        east: 11.5,
      );
    // The mirror's manifest says 11.2; this build reads up to 11.1.
    final harness = await pumpTiles(
      tester,
      map: map,
      extraOverrides: <Override>[
        supportedRd5FormatProvider.overrideWith(
          (ref) async => const Rd5Format(11, 1),
        ),
      ],
    );

    await tester.tap(find.text(l10n.routingTilesVisibleArea));
    await tester.pumpAndSettle();

    expect(find.text(l10n.routingTilesNeedsAppTitle), findsOneWidget);
    expect(find.text('E10_N45'), findsWidgets);
    expect(
      find.textContaining(l10n.routingTilesNeedsAppBody('11.2', '11.1')),
      findsOneWidget,
    );
    expect(find.text(l10n.routingTilesOpenStore), findsNothing);
    expect(find.text(l10n.recordingBatteryLater), findsOneWidget);

    await tester.tap(find.text(l10n.recordingBatteryLater));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        l10n.routingTilesDownloadCount(1, '').split('(').first.trim(),
      ),
      findsNothing,
    );
    expect(
      harness.adapter.requests.where((r) => r.uri.path.endsWith('.rd5')),
      isEmpty,
    );
    await unmountTiles(tester);
  });
}
