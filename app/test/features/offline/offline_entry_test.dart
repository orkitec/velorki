import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/offline/presentation/offline_entry.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/routing_tiles/domain/routing_tile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../support/app.dart';

RoutingTile _tile(int lon, RoutingTileState state) => RoutingTile(
  tile: TileName(lon, 40),
  bytes: 1,
  updatedAt: DateTime.utc(2026, 9, 1),
  formatVersion: '11.2',
  state: state,
);

Future<void> _pump(WidgetTester tester, List<RoutingTile> tiles) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routingTilesProvider.overrideWith((ref) => Stream.value(tiles)),
      ],
      child: testApp(home: const Scaffold(body: OfflineEntry())),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
}

void main() {
  testWidgets('with nothing to update the row is plain', (tester) async {
    await _pump(tester, [_tile(-75, RoutingTileState.ready)]);

    expect(find.text(l10n.offlineEntryTitle), findsOneWidget);
    expect(find.text(l10n.offlineEntrySubtitle), findsOneWidget);
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('rebuilt tiles are counted on the row', (tester) async {
    await _pump(tester, [
      _tile(-75, RoutingTileState.stale),
      _tile(-80, RoutingTileState.stale),
      _tile(-85, RoutingTileState.ready),
    ]);

    expect(find.text(l10n.routingTilesUpdatesHint(2)), findsOneWidget);
    expect(find.widgetWithText(Badge, '2'), findsOneWidget);
  });

  testWidgets('one rebuilt tile reads as one', (tester) async {
    await _pump(tester, [_tile(-75, RoutingTileState.stale)]);

    expect(find.text(l10n.routingTilesUpdatesHint(1)), findsOneWidget);
  });
}
