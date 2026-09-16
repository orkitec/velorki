import 'dart:convert';
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
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/offline/presentation/offline_screen.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../map/support/offline_fakes.dart';
import '../routing_tiles/support/fake_segments.dart';

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
  ],
};

/// The map, the tile mirror and the region store, all faked.
class _Harness {
  _Harness()
    : db = VelorkiDatabase.memory(),
      storage = BrouterStorage(tempDir('velorki-offline')) {
    storage.segments.createSync(recursive: true);
    storage.profiles.createSync(recursive: true);
  }

  final VelorkiDatabase db;
  final BrouterStorage storage;
  final FakeOfflineMapApi api = FakeOfflineMapApi();
  final FakeSegmentsAdapter adapter = FakeSegmentsAdapter((options) {
    if (options.uri.path.endsWith('manifest.json')) {
      return FakeSegmentsResponse.json(_manifest());
    }
    return FakeSegmentsResponse.bytes(_body);
  });

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

Future<_Harness> _pump(WidgetTester tester, {FakeMapController? map}) async {
  final h = _Harness();
  addTearDown(h.db.close);
  await tester.binding.setSurfaceSize(const Size(1080, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...h.overrides,
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
        home: OfflineScreen(mapController: map),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

/// Lets the real downloads run: the tile through dio's fake adapter and the
/// region through the fake offline API, both on real async I/O.
Future<void> _runDownloads(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

FakeMapController _mapOverTyrol() => FakeMapController()
  ..visibleBounds = const BoundingBox(
    south: 46.0,
    west: 10.5,
    north: 47.0,
    east: 11.5,
  );

void main() {
  testWidgets('explains both kinds, their sources, and why the download is '
      'off without a map', (tester) async {
    await _pump(tester);

    expect(find.text('Offline'), findsOneWidget);
    expect(
      find.textContaining('Two things make a ride work without a signal'),
      findsOneWidget,
    );
    expect(find.textContaining('OpenFreeMap'), findsOneWidget);
    expect(
      find.textContaining('BRouter tiles from the Velorki mirror'),
      findsOneWidget,
    );
    expect(find.text('No areas downloaded'), findsOneWidget);
    expect(find.text('Nothing downloaded yet'), findsOneWidget);
    expect(find.text('Manage'), findsNWidgets(2));
    expect(
      find.textContaining('Open this screen from the map'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Download the visible area'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    await _unmount(tester);
  });

  testWidgets('one confirmation downloads the map and the routing tile', (
    tester,
  ) async {
    final h = await _pump(tester, map: _mapOverTyrol());

    await tester.tap(find.text('Download the visible area'));
    await tester.pumpAndSettle();

    expect(find.text('Download the visible area'), findsNWidgets(2));
    expect(find.textContaining('Map of the visible area'), findsOneWidget);
    expect(find.textContaining('E10_N45 ·'), findsOneWidget);
    expect(
      find.textContaining('Start a download when you are on Wi-Fi'),
      findsWidgets,
    );

    await tester.tap(find.text('Download'));
    await _runDownloads(tester);
    await tester.pumpAndSettle();

    expect(h.api.downloads, hasLength(1));
    expect(h.api.downloads.single.bounds.south, 46.0);
    expect(h.storage.segments.listSync().map((f) => f.path.split('/').last), [
      'E10_N45.rd5',
    ]);
    expect(find.textContaining('1 area'), findsOneWidget);
    expect(find.textContaining('1 tile'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('cancelling the confirmation downloads nothing', (tester) async {
    final h = await _pump(tester, map: _mapOverTyrol());

    await tester.tap(find.text('Download the visible area'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await _runDownloads(tester);

    expect(h.api.downloads, isEmpty);
    expect(h.storage.segments.listSync(), isEmpty);
    await _unmount(tester);
  });

  testWidgets('Manage opens the map areas and the routing tiles screens', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Manage').first);
    await tester.pumpAndSettle();
    expect(find.text('Offline maps'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manage').last);
    await tester.pumpAndSettle();
    expect(find.text('Offline routing data'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _unmount(tester);
  });
}
