import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/presentation/map_attribution.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/map_strings.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki_geo/velorki_geo.dart';

Future<Widget> _wrap(Widget child, {bool cyclosm = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'map.cyclosm_overlay': cyclosm,
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('MapAttributionChip', () {
    testWidgets('names OpenStreetMap and OpenFreeMap', (tester) async {
      await tester.pumpWidget(await _wrap(const MapAttributionChip()));

      expect(
        find.text(
          '${MapStrings.attributionOsm} · ${MapStrings.attributionOpenFreeMap}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('adds CyclOSM while the overlay is on', (tester) async {
      await tester.pumpWidget(
        await _wrap(const MapAttributionChip(), cyclosm: true),
      );

      expect(
        find.textContaining(MapStrings.attributionCyclosm),
        findsOneWidget,
      );
    });

    testWidgets('opens the licence dialog with the source URLs', (
      tester,
    ) async {
      await tester.pumpWidget(await _wrap(const MapAttributionChip()));

      await tester.tap(find.byType(MapAttributionChip));
      await tester.pumpAndSettle();

      expect(find.text(MapStrings.attributionTitle), findsWidgets);
      expect(find.text(MapStrings.attributionOsmUrl), findsOneWidget);
      expect(find.text(MapStrings.attributionOpenFreeMapUrl), findsOneWidget);
      // Not active, so it is not listed.
      expect(find.text(MapStrings.attributionCyclosmUrl), findsNothing);

      await tester.tap(find.text(MapStrings.close));
      await tester.pumpAndSettle();
      expect(find.text(MapStrings.attributionOsmUrl), findsNothing);
    });
  });

  group('MapControls', () {
    testWidgets('is inert without a controller', (tester) async {
      await tester.pumpWidget(await _wrap(const MapControls(controller: null)));

      final zoomIn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(zoomIn.onPressed, isNull);
    });

    testWidgets('zooms in and out around the current centre', (tester) async {
      final controller = FakeMapController()
        ..center = const LatLng(47.0, 8.0)
        ..zoom = 10;

      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pump();
      expect(controller.cameraMoves.last.zoom, 11);
      expect(controller.cameraMoves.last.center, const LatLng(47.0, 8.0));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.remove));
      await tester.pump();
      expect(controller.cameraMoves.last.zoom, 10);
    });

    testWidgets('clamps the zoom to the MapLibre range', (tester) async {
      final controller = FakeMapController()
        ..center = const LatLng(0, 0)
        ..zoom = 22;

      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pump();

      expect(controller.cameraMoves.single.zoom, 22);
    });

    testWidgets('toggles the CyclOSM overlay and remembers it', (tester) async {
      final controller = FakeMapController();
      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));
      final element = tester.element(find.byType(MapControls));
      final container = ProviderScope.containerOf(element);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.directions_bike));
      await tester.pumpAndSettle();

      expect(controller.cyclosmOverlayCalls, [true]);
      expect(container.read(cyclosmOverlayProvider), isTrue);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.directions_bike));
      await tester.pumpAndSettle();

      expect(controller.cyclosmOverlayCalls, [true, false]);
      expect(container.read(cyclosmOverlayProvider), isFalse);
    });
  });
}
