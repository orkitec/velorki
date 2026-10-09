import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/domain/cycle_map.dart';
import 'package:velorki/features/map/domain/stops_along_route.dart';
import 'package:velorki/features/map/presentation/layers_sheet.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/stops_ahead_line.dart';
import 'package:velorki/features/map/presentation/visible_map_padding.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/search_field.dart'
    show gazetteerPoiKindLabel;
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';

const List<Size> _upright = <Size>[
  Size(375, 667),
  Size(360, 800),
  Size(411, 914),
];
const List<Size> _sideways = <Size>[Size(667, 375), Size(874, 402)];

Future<void> _screen(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<SharedPreferences> _pump(
  WidgetTester tester, {
  MapStopsOffer offer = MapStopsOffer.plan,
  List<Override> overrides = const <Override>[],
  bool stopsShown = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (stopsShown) 'map.stops.shown': true,
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ],
      child: testApp(
        home: Scaffold(
          body: MapChromeInsets(
            stopsOffer: offer,
            child: Align(
              alignment: Alignment.topRight,
              child: MapControls(controller: FakeMapController()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return prefs;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.layers_outlined));
  await tester.pumpAndSettle();
  expect(find.byType(LayersSheet), findsOneWidget);
}

Finder _switch(String title) => find.widgetWithText(SwitchListTile, title);

final GuidedRoute _route = GuidedRoute(
  key: 'r1',
  line: const <LatLng>[LatLng(48, 11), LatLng(48, 11.1)],
  turns: const [],
);

SearchResult _stop(String kind) => SearchResult(
  name: '',
  position: const LatLng(48, 11.05),
  source: SearchSource.local,
  kind: SearchKind.poi,
  detail: kind,
);

void main() {
  group('the Layers button', () {
    for (final (size, count) in <(Size, int)>[
      (const Size(375, 667), 4),
      (const Size(411, 914), 5),
    ]) {
      testWidgets('takes the cycle map button\'s place: $count buttons at '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await _screen(tester, size);
        await _pump(tester);

        final buttons = find.descendant(
          of: find.byType(MapControls),
          matching: find.byType(IconButton),
        );
        // Locate, layers, (download,) zoom in, zoom out: as many as with
        // the cycle map button before.
        expect(buttons, findsNWidgets(count));
        expect(find.byIcon(Icons.directions_bike), findsNothing);
        expect(find.byTooltip(l10n.mapLayers), findsOneWidget);
      });
    }

    testWidgets('is in the accent while the stops are shown', (tester) async {
      await _screen(tester, const Size(411, 914));
      final prefs = await _pump(tester);
      Color? color() => tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.layers_outlined),
          )
          .style
          ?.foregroundColor
          ?.resolve(<WidgetState>{});
      final idle = color();

      await prefs.setBool('map.stops.shown', true);
      final element = tester.element(find.byType(MapControls));
      ProviderScope.containerOf(element)
          .invalidate(mapStopsPreferencesProvider);
      await tester.pump();

      expect(color(), isNot(idle));
    });
  });

  group('the Layers sheet', () {
    for (final size in <Size>[..._upright, ..._sideways]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('fits on Plan at $label', (tester) async {
        debugShellLayoutOverride = null;
        await _screen(tester, size);
        // On, so the sheet is at its tallest.
        await _pump(tester, stopsShown: true);
        await _openSheet(tester);

        expect(find.text(l10n.mapLayers), findsWidgets);
        expect(_switch(l10n.mapLayersCycleMap), findsOneWidget);
        expect(_switch(l10n.mapLayersStops), findsOneWidget);
        expect(find.text(l10n.mapLayersStopsPlanHint), findsOneWidget);
        // Not on Plan: there is no route followed there.
        expect(find.byType(SegmentedButton<bool>), findsNothing);
        expect(
          find.text(gazetteerPoiKindLabel(l10n, 'drinking_water')!),
          findsOneWidget,
        );
        expect(
          find.text(gazetteerPoiKindLabel(l10n, 'camp_site')!),
          findsOneWidget,
        );
        expect(
          find.text(gazetteerPoiKindLabel(l10n, 'museum')!),
          findsOneWidget,
        );
        expect(find.byType(FilterChip), findsWidgets);
        expectNoClippedText(tester);
      });

      testWidgets('fits on a guided ride at $label', (tester) async {
        debugShellLayoutOverride = null;
        await _screen(tester, size);
        await _pump(
          tester,
          offer: MapStopsOffer.ride,
          overrides: [activeGuidedRouteProvider.overrideWithValue(_route)],
          stopsShown: true,
        );
        await _openSheet(tester);

        expect(find.text(l10n.mapLayersStopsRideHint), findsOneWidget);
        expect(find.byType(SegmentedButton<bool>), findsOneWidget);
        expect(find.text(l10n.mapLayersAlongRoute), findsOneWidget);
        expect(find.text(l10n.mapLayersInArea), findsOneWidget);
        expectNoClippedText(tester);
      });
    }

    testWidgets('on a map that is not the shared one, only the cycle map', (
      tester,
    ) async {
      await _screen(tester, const Size(411, 914));
      await _pump(tester, offer: MapStopsOffer.none);
      await _openSheet(tester);

      expect(_switch(l10n.mapLayersCycleMap), findsOneWidget);
      expect(_switch(l10n.mapLayersStops), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('on the Record tab without a route, no choice of where', (
      tester,
    ) async {
      await _screen(tester, const Size(411, 914));
      await _pump(
        tester,
        offer: MapStopsOffer.ride,
        overrides: [activeGuidedRouteProvider.overrideWithValue(null)],
      );
      await _openSheet(tester);

      expect(_switch(l10n.mapLayersStops), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
    });

    testWidgets('the online cycle map switch is the app-wide overlay', (
      tester,
    ) async {
      await _screen(tester, const Size(411, 914));
      final prefs = await _pump(tester);
      await _openSheet(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LayersSheet)),
      );

      await tester.tap(_switch(l10n.mapLayersOnlineCycleMap));
      await tester.pumpAndSettle();
      expect(container.read(cyclosmOverlayProvider), isTrue);
      expect(prefs.getBool('map.cyclosm_overlay'), isTrue);

      await tester.tap(_switch(l10n.mapLayersOnlineCycleMap));
      await tester.pumpAndSettle();
      expect(container.read(cyclosmOverlayProvider), isFalse);
    });

    testWidgets('the cycle map switch unfolds its parts, remembered', (
      tester,
    ) async {
      await _screen(tester, const Size(411, 914));
      final prefs = await _pump(tester);
      await _openSheet(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LayersSheet)),
      );
      final surface = find.widgetWithText(FilterChip, l10n.mapCyclePartSurface);
      expect(surface, findsNothing);

      await tester.tap(_switch(l10n.mapLayersCycleMap));
      await tester.pumpAndSettle();
      expect(container.read(cycleMapPreferencesProvider).shown, isTrue);
      expect(prefs.getBool('map.cycle_map.shown'), isTrue);
      expect(find.byType(CycleMapPartSample), findsNWidgets(8));

      await tester.ensureVisible(surface);
      await tester.tap(surface);
      await tester.pumpAndSettle();
      expect(
        container.read(cycleMapPreferencesProvider).parts,
        contains(CycleMapPart.surface),
      );
      expect(prefs.getStringList('map.cycle_map.parts'), contains('surface'));
    });

    testWidgets('the two cycle maps take turns', (tester) async {
      await _screen(tester, const Size(411, 914));
      await _pump(tester);
      await _openSheet(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LayersSheet)),
      );

      await tester.tap(_switch(l10n.mapLayersOnlineCycleMap));
      await tester.pumpAndSettle();
      await tester.tap(_switch(l10n.mapLayersCycleMap));
      await tester.pumpAndSettle();
      expect(container.read(cycleMapPreferencesProvider).shown, isTrue);
      expect(container.read(cyclosmOverlayProvider), isFalse);

      await tester.ensureVisible(_switch(l10n.mapLayersOnlineCycleMap));
      await tester.tap(_switch(l10n.mapLayersOnlineCycleMap));
      await tester.pumpAndSettle();
      expect(container.read(cyclosmOverlayProvider), isTrue);
      expect(container.read(cycleMapPreferencesProvider).shown, isFalse);
    });

    testWidgets('the stops switch, the kinds and the where are remembered', (
      tester,
    ) async {
      await _screen(tester, const Size(411, 914));
      final prefs = await _pump(
        tester,
        offer: MapStopsOffer.ride,
        overrides: [activeGuidedRouteProvider.overrideWithValue(_route)],
      );
      await _openSheet(tester);

      await tester.tap(_switch(l10n.mapLayersStops));
      await tester.pumpAndSettle();
      expect(prefs.getBool('map.stops.shown'), isTrue);

      // A kind off by default goes on, one on by default goes off.
      final campsite = find.widgetWithText(
        FilterChip,
        gazetteerPoiKindLabel(l10n, 'camp_site')!,
      );
      await tester.ensureVisible(campsite);
      await tester.pumpAndSettle();
      await tester.tap(campsite);
      await tester.pumpAndSettle();
      final cafe = find.widgetWithText(
        FilterChip,
        gazetteerPoiKindLabel(l10n, 'cafe')!,
      );
      await tester.ensureVisible(cafe);
      await tester.pumpAndSettle();
      await tester.tap(cafe);
      await tester.pumpAndSettle();

      final kinds = prefs.getStringList('map.stops.kinds')!;
      expect(kinds, contains('camp_site'));
      expect(kinds, isNot(contains('cafe')));
      expect(tester.widget<FilterChip>(campsite).selected, isTrue);
      expect(tester.widget<FilterChip>(cafe).selected, isFalse);
      // A picked chip is the accent colour: its icon goes with its label.
      Color? iconColor(Finder chip) => tester
          .widget<Icon>(find.descendant(of: chip, matching: find.byType(Icon)))
          .color;
      final scheme = Theme.of(tester.element(campsite)).colorScheme;
      expect(iconColor(campsite), scheme.onPrimary);
      expect(iconColor(cafe), isNull);

      await tester.ensureVisible(find.text(l10n.mapLayersInArea));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.mapLayersInArea));
      await tester.pumpAndSettle();
      expect(prefs.getBool('map.stops.alongRoute'), isFalse);
    });

    testWidgets('with the stops off their choices fold away, and come back '
        'as they were', (tester) async {
      await _screen(tester, const Size(411, 914));
      final prefs = await _pump(
        tester,
        offer: MapStopsOffer.ride,
        overrides: [activeGuidedRouteProvider.overrideWithValue(_route)],
      );
      await _openSheet(tester);
      expect(prefs.getBool('map.stops.shown'), isNull);
      // Off: no kinds and no choice of where to show them.
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text(l10n.mapLayersInArea), findsNothing);

      await tester.tap(_switch(l10n.mapLayersStops));
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsWidgets);
      expect(find.text(l10n.mapLayersInArea), findsOneWidget);
      final toilets = find.widgetWithText(
        FilterChip,
        gazetteerPoiKindLabel(l10n, 'toilets')!,
      );
      await tester.ensureVisible(toilets);
      await tester.pumpAndSettle();
      await tester.tap(toilets);
      await tester.pumpAndSettle();

      // Off and on again: the pick is kept.
      await tester.ensureVisible(_switch(l10n.mapLayersStops));
      await tester.tap(_switch(l10n.mapLayersStops));
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      await tester.tap(_switch(l10n.mapLayersStops));
      await tester.pumpAndSettle();
      expect(
        prefs.getStringList('map.stops.kinds'),
        isNot(contains('toilets')),
      );
      expect(tester.widget<FilterChip>(toilets).selected, isFalse);
    });
  });

  group('the stops ahead line', () {
    testWidgets('three entries fit beside the column at 360 wide', (
      tester,
    ) async {
      await _screen(tester, const Size(360, 800));
      final tapped = <SearchResult>[];
      final entries = <StopAlongRoute<SearchResult>>[
        for (final (kind, ahead) in <(String, double)>[
          ('bicycle_repair_station', 400),
          ('drinking_water', 1250),
          ('toilets', 12600),
        ])
          StopAlongRoute<SearchResult>(
            stop: _stop(kind),
            atM: ahead,
            offM: 20,
            aheadM: ahead,
          ),
      ];
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: testApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: mapControlsWidth(context) + 8,
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: StopsAheadLine(entries: entries, onTap: tapped.add),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final kind in <String>[
        'bicycle_repair_station',
        'drinking_water',
        'toilets',
      ]) {
        expect(
          find.textContaining(gazetteerPoiKindLabel(l10n, kind)!),
          findsOneWidget,
        );
      }
      expectNoClippedText(tester);

      await tester.tap(
        find.textContaining(gazetteerPoiKindLabel(l10n, 'toilets')!),
      );
      expect(tapped.single.detail, 'toilets');
    });

    testWidgets('no stops ahead, no line', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            home: StopsAheadLine(entries: const [], onTap: (_) {}),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
    });
  });
}
