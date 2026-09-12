// On-device check for milestone M1: the real app plans a route through the
// configured BRouter server. Run against an emulator with a local server:
//
//   flutter test integration_test/plan_route_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_BROUTER_URL=http://10.0.2.2:17777 \
//     --dart-define=VELORKI_API_URL=
//
// The coordinates are on Madeira, one of the two tiles the oracle harness in
// tools/brouter-oracle serves.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/map/presentation/map_view.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plans a route on Madeira through BRouter', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        mapViewBuilderProvider.overrideWithValue(
          (onReady) => MapView(onControllerReady: onReady),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const VelorkiApp(),
      ),
    );
    // The map is a platform view with its own animations; do not pumpAndSettle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    final planner = container.read(plannerControllerProvider.notifier);
    planner.addWaypoint(const LatLng(32.650, -16.920)); // Funchal
    planner.addWaypoint(const LatLng(32.700, -16.850)); // via, inland
    planner.addWaypoint(const LatLng(32.720, -16.770)); // Machico

    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 250));
      final state = container.read(plannerControllerProvider);
      if (state.route.hasError) {
        fail('routing failed: ${state.route.error}');
      }
      if (state.error != null) {
        fail('planner error: ${state.error}');
      }
      final result = state.result;
      if (result != null && !state.isRouting) {
        debugPrint(
          'VELORKI_ROUTE length=${result.lengthM.round()}m '
          'ascent=${result.ascentM.round()}m points=${result.geometry.length} '
          'elapsed=${stopwatch.elapsedMilliseconds}ms '
          'paved=${result.surfaceStats.pavedShare.toStringAsFixed(2)}',
        );
        expect(result.lengthM, greaterThan(10000));
        expect(result.geometry.length, greaterThan(100));
        return;
      }
    }
    fail('no route within 30 s');
  });
}
