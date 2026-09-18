// Plan, save, and find the route again: the dialog, the library list, the
// detail screen's stats and "Open in planner".
//
//   flutter test integration_test/save_library_detail_test.dart \
//     -d emulator-5554 --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL=
//
// The route is saved into the app's real drift database on the device, so the
// name carries a timestamp: the emulator keeps its data between runs and two
// runs must not collide.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/presentation/route_stats_row.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saves a route, opens it from the library and back in the '
      'planner', (tester) async {
    final container = await pumpApp(
      tester,
      overrides: [
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        positionSourceProvider.overrideWithValue(
          FixedPositionSource(region.start),
        ),
      ],
    );
    await ensureRegionTile(tester, container);

    final planner = container.read(plannerControllerProvider.notifier);
    planner
      ..addWaypoint(region.start)
      ..addWaypoint(region.via)
      ..addWaypoint(region.end);

    await pumpFor(tester, const Duration(milliseconds: 400));
    await waitUntil(
      tester,
      () {
        final state = container.read(plannerControllerProvider);
        if (state.route.hasError) fail('routing failed: ${state.route.error}');
        return state.canSave && !state.isRouting;
      },
      describe: 'a saveable route',
      timeout: const Duration(seconds: 90),
      onTimeout: () => '${container.read(plannerControllerProvider)}',
    );

    final planned = container.read(plannerControllerProvider);
    final lengthM = planned.result!.lengthM;
    final name = 'Itest saved ${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('VELORKI_SAVE planning ${lengthM.round()}m as $name');

    // savedRoutesProvider is autoDispose; keep it subscribed so the test can
    // read it back instead of watching it build and tear down again.
    final routes = container.listen(savedRoutesProvider, (_, _) {});
    addTearDown(routes.close);

    // ------------------------------------------------------------ the dialog
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Save'));
    await waitForWidget(tester, find.byType(AlertDialog));
    expect(find.text('Save route'), findsOneWidget);

    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    // The dialog offers "Route <date>"; replacing it proves the field is live.
    expect(
      tester.widget<TextField>(field).controller!.text,
      startsWith('Route '),
    );
    await tester.enterText(field, name);
    await pumpFor(tester, const Duration(milliseconds: 200));
    await tapAndPump(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Save'),
      ),
    );

    expect(find.text('Route saved'), findsOneWidget);
    await waitUntil(
      tester,
      () => routes.read().value?.any((route) => route.name == name) ?? false,
      describe: 'the saved route in the database',
      onTimeout: () => '${routes.read()}',
    );
    final saved = routes.read().value!.firstWhere((r) => r.name == name);
    expect(container.read(plannerControllerProvider).savedRouteId, saved.id);

    // ----------------------------------------------------------- the library
    await tapAndPump(tester, find.text('Library'));
    // The Library remembers its last segment across launches, and another
    // test may have left it on the rides; this one wants the routes.
    await tapAndPump(tester, find.text('Routes'));
    final row = find.widgetWithText(ListTile, name);
    await waitForWidget(tester, row);
    await tapAndPump(tester, row);

    // ------------------------------------------------------- the detail page
    await waitForWidget(tester, find.byType(RouteStatsRow));
    final stats = tester.widget<RouteStatsRow>(find.byType(RouteStatsRow));
    expect(stats.distanceM, closeTo(lengthM, 1));

    final distanceTile = tester.widget<StatTile>(
      find.ancestor(of: find.text('DISTANCE'), matching: find.byType(StatTile)),
    );
    debugPrint('VELORKI_SAVE detail DISTANCE=${distanceTile.value}');
    expect(distanceTile.label, 'Distance');
    expect(distanceTile.value, contains('km'));
    await screenshot(tester, 'route-detail');

    // ---------------------------------------------------- back to the planner
    // Clearing first makes "Open in planner" prove it restored the plan rather
    // than that the plan happened to still be there.
    container.read(plannerControllerProvider.notifier).clear();
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(container.read(plannerControllerProvider).isEmpty, isTrue);

    await tapAndPump(
      tester,
      find.widgetWithText(FilledButton, 'Open in planner'),
    );
    await waitUntil(
      tester,
      () => container.read(plannerControllerProvider).savedRouteId == saved.id,
      describe: 'the plan restored from the library',
      onTimeout: () => '${container.read(plannerControllerProvider)}',
    );

    final restored = container.read(plannerControllerProvider);
    expect(restored.savedRouteName, name);
    expect(
      restored.waypoints.map((w) => w.pos),
      planned.waypoints.map((w) => w.pos),
    );
    expect(restored.result!.lengthM, closeTo(lengthM, 1));
    expect(find.byType(SearchField), findsOneWidget);

    await unmountApp(tester);
  });
}
