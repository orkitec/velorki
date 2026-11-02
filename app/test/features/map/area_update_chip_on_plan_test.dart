import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/platform_features.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/presentation/stops_download_chip.dart';
import 'package:velorki/features/offline/presentation/area_update_chip.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/routing_tiles/domain/routing_tile.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show TileName;
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart';
import '../routing_tiles/support/fake_segments.dart';

/// Inside E10_N45.
const BoundingBox _overTyrol = BoundingBox(
  south: 48.0,
  west: 11.0,
  north: 48.1,
  east: 11.1,
);

Future<PlannerHarness> _pumpPlan(
  WidgetTester tester, {
  required bool covered,
}) async {
  final harness = PlannerHarness();
  harness.stopsCoverage.covered = (_) => covered;
  final root = tempDir('velorki-update-chip');
  final repository = RoutingTilesRepository(
    dao: harness.db.routingTilesDao,
    segmentsDir: Directory('${root.path}/segments')..createSync(),
    gazetteerDir: Directory('${root.path}/gazetteer')..createSync(),
  );
  File(repository.gazetteerFileFor(const TileName(10, 45)).path)
      .writeAsStringSync('gaz');
  final tile = RoutingTile(
    tile: const TileName(10, 45),
    bytes: 1,
    updatedAt: DateTime.utc(2026, 9),
    formatVersion: '11.2',
    state: RoutingTileState.stale,
  );
  final h = await pumpScreen(
    tester,
    const PlannerScreen(),
    harness: harness,
    surfaceSize: const Size(360, 780),
    extraOverrides: [
      noMirrorOverride,
      // No map areas to download beside the routing data, as in a browser.
      platformFeaturesProvider.overrideWithValue(PlatformFeatures.browser),
      routingTilesRepositoryProvider.overrideWith((ref) async => repository),
      routingTilesProvider.overrideWith((ref) => Stream.value([tile])),
    ],
  );
  h.map
    ..zoom = 13
    ..center = const LatLng(48.05, 11.05)
    ..visibleBounds = _overTyrol;
  for (final listener in [...h.map.cameraIdleListeners]) {
    listener();
  }
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('Plan: an area with new map data offers the update over the '
      'map, a tap asks for it in place, and it can be closed', (tester) async {
    await _pumpPlan(tester, covered: true);

    expect(find.text(l10n.mapAreaUpdateAvailable), findsOneWidget);
    expect(find.text(l10n.mapAreaUpdate), findsOneWidget);
    expect(find.text(l10n.searchAreaNotDownloaded), findsNothing);
    expectNoClippedText(tester);

    // The update is planned from the mirror, which is out of reach here: the
    // failure comes up in place, no screen is pushed.
    await tester.tap(find.text(l10n.mapAreaUpdate));
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byType(SnackBar).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(l10n.offlineTitle), findsNothing);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.mapAreaHintHide));
    await tester.pumpAndSettle();
    expect(find.byType(AreaUpdateChip), findsOneWidget);
    expect(find.text(l10n.mapAreaUpdateAvailable), findsNothing);
  });

  testWidgets('Plan: the not-downloaded chip wins over the update chip', (
    tester,
  ) async {
    await _pumpPlan(tester, covered: false);

    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);
    expect(find.text(l10n.mapAreaUpdateAvailable), findsNothing);
    expect(find.byType(StopsDownloadChip), findsOneWidget);
  });
}
