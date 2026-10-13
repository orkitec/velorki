import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/tables/routes.dart';
import 'package:velorki/features/library/data/route_turns_on_map.dart';
import 'package:velorki/features/navigation/presentation/cue_sheet_list.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';

/// An imported route with two turns the file named.
Future<SavedRoute> _seed(PlannerHarness h, {bool generated = false}) async {
  final routes = RouteRepository(
    h.db.routesDao,
    clock: () => DateTime.utc(2026, 10, 12, 10),
  );
  final saved = await routes.saveImportedRoute(
    name: 'Two turns',
    points: syntheticRoute().geometry,
    source: RouteSource.importedGpx,
    turns: const <TurnHint>[
      TurnHint(pointIndex: 1, kind: TurnKind.right, note: 'Right at the barn'),
      TurnHint(pointIndex: 3, kind: TurnKind.left, note: 'Left at the mill'),
    ],
  );
  if (!generated) return saved;
  await h.db.routesDao.updateRoute(
    (await h.db.routesDao.routeById(saved.id))!.copyWith(turnsGenerated: true),
  );
  return saved;
}

Finder get _switch => find.descendant(
  of: find.byType(CueSheetList),
  matching: find.byType(Switch),
);

void main() {
  testWidgets('the turns are off the map until the switch in the cue sheet '
      'puts them on, and the choice is kept', (tester) async {
    final h = PlannerHarness();
    final saved = await _seed(h);
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();

    // Off by default: the ends are there, the turns are not.
    expect(h.map.turnMarkers, isEmpty);
    expect(h.map.waypoints, hasLength(2));
    expect(find.text(l10n.cueSheetShowOnMap), findsOneWidget);
    expect(tester.widget<Switch>(_switch).value, isFalse);

    // A turn picked in the list is still shown on the map.
    await tester.ensureVisible(find.text('Right at the barn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Right at the barn'));
    await tester.pumpAndSettle();
    final line = syntheticRoute().positions;
    expect(h.map.searchPin, line[1]);
    expect(h.map.turnMarkers, isEmpty);

    await tester.tap(_switch);
    await tester.pumpAndSettle();
    expect(h.map.turnMarkers.map((m) => m.position), [line[1], line[3]]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('routes.turnsOnMap'), isTrue);

    await tester.tap(_switch);
    await tester.pumpAndSettle();
    expect(h.map.turnMarkers, isEmpty);
    expect(prefs.getBool('routes.turnsOnMap'), isNull);
    await unmountApp(tester);
  });

  test('the choice comes back from the preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'routes.turnsOnMap': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(routeTurnsOnMapProvider), isTrue);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final empty = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(empty.dispose);
    expect(empty.read(routeTurnsOnMapProvider), isFalse);
  });

  testWidgets('turns made from the map say so under the caption', (
    tester,
  ) async {
    final h = PlannerHarness();
    final saved = await _seed(h, generated: true);
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.cueSheetTurnsFromMap), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a file\'s own turns carry no such note', (tester) async {
    final h = PlannerHarness();
    final saved = await _seed(h);
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(saved.id),
      harness: h,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.cueSheetTurnsFromMap), findsNothing);
    expect(_switch, findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a route without turns has no switch', (tester) async {
    final h = PlannerHarness();
    final plain = await RouteRepository(h.db.routesDao).saveImportedRoute(
      name: 'No turns',
      points: syntheticRoute().geometry,
      source: RouteSource.importedGpx,
    );
    await pumpApp(
      tester,
      initialLocation: routeDetailLocation(plain.id),
      harness: h,
    );
    await tester.pumpAndSettle();
    expect(find.byType(CueSheetList), findsOneWidget);
    expect(_switch, findsNothing);
    await unmountApp(tester);
  });
}
