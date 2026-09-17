import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
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
      find.text(l10n.routingTilesDownloadCount(1, '125 MB')),
      findsOneWidget,
    );
    // The rider gets one clear action, not a snack bar they cannot act on.
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text(l10n.routingTilesDownloadCount(1, '125 MB')));
    await tester.pumpAndSettle();

    expect(find.byType(RoutingTilesScreen), findsOneWidget);
    expect(find.text(l10n.routingTilesRouteTitle), findsOneWidget);
    expect(find.text('E10_N45'), findsOneWidget);

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
    expect(find.textContaining('position not mapped'), findsWidgets);

    await unmountApp(tester);
  });
}
