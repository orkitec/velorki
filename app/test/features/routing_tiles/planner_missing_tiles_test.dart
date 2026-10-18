import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/platform_features.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/routing_tiles/application/tile_download_controller.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki/features/routing_tiles/presentation/routing_tiles_screen.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';
import 'support/fake_segments.dart';

const TileName _tile = TileName(10, 45);
const LatLng _a = LatLng(47.0, 11.0);
const LatLng _b = LatLng(47.1, 11.1);

Map<String, Object?> _manifest() => <String, Object?>{
  'formatVersion': '11.2',
  'tiles': <Object?>[
    <String, Object?>{
      'tile': 'E10_N45',
      'bytes': 131072000,
      'updatedAt': '2026-09-12T01:03:00Z',
      // The offline search index comes down with the tile, and the rider is
      // quoted both: 125 MB + 20 MB.
      'gazetteer': <String, Object?>{'bytes': 20971520, 'sha256': 'GAZHASH'},
    },
  ],
};

List<Override> _overrides(BrouterStorage storage) => <Override>[
  appConfigProvider.overrideWithValue(
    const AppConfig(segmentsUrl: 'https://mirror.test/segments4'),
  ),
  brouterStorageProvider.overrideWith((ref) async => storage),
  brouterProfilesProvider.overrideWith((ref) async => storage.profiles),
  segmentsDioProvider.overrideWithValue(
    segmentsDioWith(
      FakeSegmentsAdapter((_) => FakeSegmentsResponse.json(_manifest())),
    ),
  ),
];

void main() {
  late BrouterStorage storage;

  setUp(() {
    storage = BrouterStorage(tempDir('velorki-planner-tiles'))
      ..segments.createSync(recursive: true)
      ..profiles.createSync(recursive: true);
  });

  testWidgets('a route with no tiles offers the download instead of an error', (
    tester,
  ) async {
    final backend = FakeRoutingBackend()
      ..error = const RoutingException(
        kind: RoutingErrorKind.missingTiles,
        message: 'no tiles for this route',
        missingTiles: <TileName>[_tile],
      );
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(backend: backend),
      extraOverrides: _overrides(storage),
    );

    h.map.onTap!(_a);
    h.map.onTap!(_b);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text(l10n.plannerMissingTiles), findsOneWidget);
    expect(
      find.text(l10n.routingTilesDownloadCount(1, '145 MB')),
      findsOneWidget,
    );
    // The rider gets one clear action, not a snack bar they cannot act on.
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text(l10n.routingTilesDownloadCount(1, '145 MB')));
    await tester.pumpAndSettle();

    expect(find.byType(RoutingTilesScreen), findsOneWidget);
    expect(find.text(l10n.routingTilesRouteTitle), findsOneWidget);
    expect(find.text('E10_N45'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('in a browser, which has no routing server, the tiles are '
      'fetched at once, with their progress', (tester) async {
    final backend = FakeRoutingBackend()
      ..error = const RoutingException(
        kind: RoutingErrorKind.missingTiles,
        message: 'no tiles for this route',
        missingTiles: <TileName>[_tile],
      );
    final queue = _RecordingQueue();
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(backend: backend),
      extraOverrides: [
        ..._overrides(storage),
        platformFeaturesProvider.overrideWithValue(PlatformFeatures.browser),
        tileDownloadQueueProvider.overrideWith(() => queue),
      ],
    );

    h.map.onTap!(_a);
    h.map.onTap!(_b);
    await tester.pump(const Duration(milliseconds: 400));
    // The manifest arrives, the tile is queued after that frame.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(queue.asked, <TileName>[_tile]);
    expect(find.text(l10n.plannerFetchingTiles('145 MB')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Nothing to tap: no download button, no screen to open.
    expect(
      find.text(l10n.routingTilesDownloadCount(1, '145 MB')),
      findsNothing,
    );

    // A rebuild does not queue the tile again.
    await tester.pump(const Duration(seconds: 1));
    expect(queue.asked, <TileName>[_tile]);

    await unmountApp(tester);
  });

  testWidgets('any other failure is still reported as before', (tester) async {
    final backend = FakeRoutingBackend()
      ..error = const RoutingException(
        kind: RoutingErrorKind.noRoute,
        message: 'position not mapped',
      );
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(backend: backend),
      extraOverrides: _overrides(storage),
    );

    h.map.onTap!(_a);
    h.map.onTap!(_b);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(l10n.plannerRoutingFailed(l10n.routingErrorNoRoute)),
      findsWidgets,
    );

    await unmountApp(tester);
  });
}

/// A download queue that records what it is asked for and reports it as
/// running, downloading nothing.
class _RecordingQueue extends TileDownloadQueue {
  final List<TileName> asked = <TileName>[];

  @override
  Future<void> enqueue(
    Iterable<SegmentEntry> entries, {
    Iterable<SegmentEntry> gazetteersOnly = const <SegmentEntry>[],
  }) async {
    asked.addAll(entries.map((e) => e.tile));
    state = state.copyWith(current: asked.first);
  }
}
