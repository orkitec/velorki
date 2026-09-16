import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/offline/presentation/offline_entry.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/routing_tiles/domain/routing_tile.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

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
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: OfflineEntry()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with nothing to update the row is plain', (tester) async {
    await _pump(tester, [_tile(-75, RoutingTileState.ready)]);

    expect(find.text('Offline data'), findsOneWidget);
    expect(
      find.text('Maps and routing data for rides without a signal'),
      findsOneWidget,
    );
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('rebuilt tiles are counted on the row', (tester) async {
    await _pump(tester, [
      _tile(-75, RoutingTileState.stale),
      _tile(-80, RoutingTileState.stale),
      _tile(-85, RoutingTileState.ready),
    ]);

    expect(find.text('2 tiles have updates'), findsOneWidget);
    expect(find.widgetWithText(Badge, '2'), findsOneWidget);
  });

  testWidgets('one rebuilt tile reads as one', (tester) async {
    await _pump(tester, [_tile(-75, RoutingTileState.stale)]);

    expect(find.text('1 tile has an update'), findsOneWidget);
  });
}
