import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/rd5_format_support.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki/features/routing_tiles/domain/rd5_format.dart';
import 'package:velorki/features/routing_tiles/presentation/routing_tiles_screen.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

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
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutingTilesScreen(mapController: map, preselected: preselected),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

    expect(find.text('Offline routing data'), findsOneWidget);
    expect(
      find.textContaining('also works for place search'),
      findsOneWidget,
      reason: 'a downloaded region brings the offline search with it',
    );
    expect(find.textContaining('No routing tiles yet'), findsOneWidget);
    expect(find.text('Nothing downloaded yet'), findsOneWidget);
    expect(
      find.textContaining('Open this screen from the map'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Download for the visible area'),
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

    await tester.tap(find.text('Download for the visible area'));
    await tester.pumpAndSettle();

    // One tile covers the whole visible box, and the manifest knows its size.
    expect(find.textContaining('E10_N45 ·'), findsOneWidget);
    expect(find.textContaining('Tiles are large'), findsWidgets);
    await tester.tap(find.textContaining('Download 1 tile'));
    await tester.pump();
    await runDownloads(tester);

    expect(harness.tileFile(_tile).existsSync(), isTrue);
    expect(find.text('E10_N45'), findsOneWidget);
    expect(find.textContaining('On this device'), findsOneWidget);
    expect(find.text('1 tile, ${_body.length} B'), findsOneWidget);
    await unmountTiles(tester);
  });

  testWidgets('a route hands its missing tiles in and they are offered', (
    tester,
  ) async {
    await pumpTiles(tester, preselected: const <TileName>[TileName(5, 45)]);

    expect(find.text('Needed for this route'), findsOneWidget);
    expect(find.text('E5_N45'), findsOneWidget);
    expect(find.text('Download 1 tile (4.0 kB)'), findsOneWidget);
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
    await tester.tap(find.text('Download for the visible area'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Download 1 tile'));
    await tester.pump();
    await runDownloads(tester);
    expect(harness.tileFile(_tile).existsSync(), isTrue);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete E10_N45?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await runDownloads(tester);

    expect(harness.tileFile(_tile).existsSync(), isFalse);
    expect(find.text('Nothing downloaded yet'), findsOneWidget);
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
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const RoutingTilesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The tile list could not be loaded'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
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

    await tester.tap(find.text('Download for the visible area'));
    await tester.pumpAndSettle();

    expect(find.text('Update Velorki first'), findsOneWidget);
    expect(find.text('E10_N45'), findsWidgets);
    expect(
      find.textContaining(
        'data format 11.2, and this Velorki reads up to 11.1',
      ),
      findsOneWidget,
    );
    expect(find.text('Open store'), findsNothing);
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Download 1 tile'), findsNothing);
    expect(
      harness.adapter.requests.where((r) => r.uri.path.endsWith('.rd5')),
      isEmpty,
    );
    await unmountTiles(tester);
  });
}
