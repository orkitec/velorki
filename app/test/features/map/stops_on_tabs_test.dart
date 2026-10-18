import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/map/application/area_download_hint.dart';
import 'package:velorki/features/map/application/cycle_map_binding.dart';
import 'package:velorki/features/map/application/map_stops_controller.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/stops_ahead_line.dart';
import 'package:velorki/features/map/presentation/stops_download_chip.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/offline/presentation/offline_screen.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/place_card.dart';
import 'package:velorki/features/search/presentation/search_field.dart'
    show gazetteerPoiKindLabel;
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show TileName;
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart';
import '../recording/support/pump.dart';

SearchResult _stop(String name, LatLng at, String kind) => SearchResult(
  name: name,
  position: at,
  source: SearchSource.local,
  kind: SearchKind.poi,
  detail: kind,
);

void main() {
  testWidgets('Plan: the stops in the area are drawn, a tap on one goes the '
      'way a searched place goes, and they leave with the tab', (tester) async {
    final fountain = _stop(
      'Brunnen',
      const LatLng(48.05, 11.05),
      'drinking_water',
    );
    final asked = <BoundingBox>[];
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      extraOverrides: [
        mapStopsFinderProvider.overrideWithValue((
          box,
          kinds,
          limit, {
          ranked = false,
        }) async {
          asked.add(box);
          final at = fountain.position;
          final inside =
              at.lat >= box.south &&
              at.lat <= box.north &&
              at.lon >= box.west &&
              at.lon <= box.east;
          return [if (inside) fountain];
        }),
      ],
    );
    const view = BoundingBox(south: 48, west: 11, north: 48.1, east: 11.1);
    h.map
      ..zoom = 14
      ..visibleBounds = view;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );

    await container.read(mapStopsPreferencesProvider.notifier).setShown(true);
    await tester.pump();
    await tester.pump(stopsDebounce * 2);
    await tester.pumpAndSettle();

    // Around what the rider sees, square by square: the sheet covers the
    // lower part, so what is asked for reaches further north than south.
    expect(asked, isNotEmpty);
    final north = asked.map((b) => b.north).reduce(math.max);
    final south = asked.map((b) => b.south).reduce(math.min);
    expect(north - view.north, greaterThan(view.south - south));
    expect(h.map.stops.single.name, 'Brunnen');

    h.map.onStopTapped!(0);
    await tester.pumpAndSettle();
    // Pinned and offered on its card, as a place picked from the search is.
    expect(h.map.searchPin, fountain.position);
    expect(find.byType(PlaceCard), findsOneWidget);
    expect(find.text(l10n.plannerSetAsStart), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, isNull);

    container.read(activeTabProvider.notifier).show(recordingRoute);
    await tester.pumpAndSettle();
    expect(h.map.stops, isEmpty);
    expect(h.map.onStopTapped, isNull);
  });

  testWidgets('Plan: zoomed out too far, nothing is drawn and nothing '
      'said', (tester) async {
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      extraOverrides: [
        mapStopsFinderProvider.overrideWithValue(
          (box, kinds, limit, {ranked = false}) async => const <SearchResult>[],
        ),
      ],
    );
    h.map
      ..zoom = stopsMinZoom - 1
      ..center = const LatLng(48.05, 11.05)
      ..visibleBounds = const BoundingBox(
        south: 47.9,
        west: 10.9,
        north: 48.2,
        east: 11.2,
      );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    await container.read(mapStopsPreferencesProvider.notifier).setShown(true);
    for (final listener in [...h.map.cameraIdleListeners]) {
      listener();
    }
    await tester.pump(stopsDebounce * 2);
    await tester.pumpAndSettle();
    expect(h.map.stops, isEmpty);
    expect(find.byType(StopsDownloadChip), findsNothing);
    expect(find.byIcon(Icons.zoom_in_rounded), findsNothing);
  });

  testWidgets('Record: along a followed route the next stops ahead are '
      'listed, and a stop tapped on the map is named', (tester) async {
    const mPerLon = 111195 * 0.66913;
    final line = <LatLng>[
      for (var m = 0.0; m <= 20000; m += 500) LatLng(48, 11 + m / mPerLon),
    ];
    LatLng beside(double km) => LatLng(48.0004, 11 + km * 1000 / mPerLon);
    final tap = _stop('', beside(2), 'drinking_water');
    final cafe = _stop('Café Rad', beside(5), 'cafe');
    final h = await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      preferences: const <String, Object>{'map.stops.shown': true},
      extraOverrides: [
        activeGuidedRouteProvider.overrideWithValue(
          GuidedRoute(key: 'r1', line: line, turns: const []),
        ),
        mapStopsFinderProvider.overrideWithValue(
          (box, kinds, limit, {ranked = false}) async => [
            for (final s in [tap, cafe])
              if (box.contains(s.position) && kinds.contains(s.detail)) s,
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(h.map.stops.map((s) => s.name), <String>['', 'Café Rad']);
    expect(find.byType(StopsAheadLine), findsOneWidget);
    expect(
      find.textContaining(gazetteerPoiKindLabel(l10n, 'drinking_water')!),
      findsOneWidget,
    );
    expect(
      find.textContaining(gazetteerPoiKindLabel(l10n, 'cafe')!),
      findsOneWidget,
    );

    // Its card names it and says what it is, and offers nothing to do
    // mid-ride; the stop stays picked out while the card is open.
    h.map.onStopTapped!(1);
    await tester.pumpAndSettle();
    final card = find.byType(PlaceCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Café Rad')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text(gazetteerPoiKindLabel(l10n, 'cafe')!),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(FilledButton)),
      findsNothing,
    );
    // No route actions; only Open in…, which every card has.
    for (final label in [
      l10n.placeCardRouteHere,
      l10n.plannerSetAsStart,
      l10n.placeCardAddStop,
      l10n.placeCardDestination,
    ]) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsNothing,
      );
    }
    expect(
      find.descendant(of: card, matching: find.text(l10n.placeCardOpenIn)),
      findsOneWidget,
    );
    expect(h.map.stops[1].selected, isTrue);

    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(h.map.stops.any((s) => s.selected), isFalse);

    // An unnamed stop is called what it is.
    h.map.onStopTapped!(0);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PlaceCard),
        matching: find.text(gazetteerPoiKindLabel(l10n, 'drinking_water')!),
      ),
      findsOneWidget,
    );
    expect(h.map.stops[0].selected, isTrue);
    // Closed by a tap beside it, it lets go of the stop too.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceCard), findsNothing);
    expect(h.map.stops[0].selected, isFalse);
  });

  testWidgets('Plan: over an area not downloaded a chip says so, also '
      'zoomed out, opens the download, and goes once the area is '
      'covered', (tester) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      // A small phone's width, where the chip has to fit in every language.
      surfaceSize: const Size(360, 780),
      extraOverrides: [
        mapStopsFinderProvider.overrideWithValue(
          (box, kinds, limit, {ranked = false}) async => const <SearchResult>[],
        ),
      ],
    );
    h.map
      // Zoomed out too far as well: the download is what helps.
      ..zoom = stopsMinZoom - 1
      ..center = const LatLng(48.05, 11.05)
      ..visibleBounds = const BoundingBox(
        south: 47.9,
        west: 10.9,
        north: 48.2,
        east: 11.2,
      );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    for (final listener in [...h.map.cameraIdleListeners]) {
      listener();
    }
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapStopsNotDownloaded), findsNothing);

    await container.read(mapStopsPreferencesProvider.notifier).setShown(true);
    for (final listener in [...h.map.cameraIdleListeners]) {
      listener();
    }
    await tester.pump(stopsDebounce * 2);
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapStopsNotDownloaded), findsOneWidget);
    expectNoClippedText(tester);

    await tester.tap(find.text(l10n.mapStopsDownload));
    await tester.pumpAndSettle();
    expect(find.byType(OfflineScreen), findsOneWidget);
    await tapBack(tester);

    // The download finished: the store re-scanned and covers the area.
    harness.stopsCoverage.changed((_) => true);
    await tester.pump(stopsDebounce * 2);
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapStopsNotDownloaded), findsNothing);
    // Zoomed out too far: nothing said in its place.
    expect(find.byType(StopsDownloadChip), findsNothing);
  });

  testWidgets('Plan: the control column stays where it is when the area '
      'chip comes, and the screen builds again under it', (tester) async {
    final harness = PlannerHarness();
    // The whole shell: the column is the shell's.
    final h = await pumpApp(
      tester,
      initialLocation: plannerRoute,
      harness: harness,
      surfaceSize: const Size(390, 844),
    );
    h.map
      ..zoom = 13
      ..center = const LatLng(48.05, 11.05)
      ..visibleBounds = const BoundingBox(
        south: 48.0,
        west: 11.0,
        north: 48.1,
        east: 11.1,
      );
    await tester.pumpAndSettle();
    final column = find.byType(MapControls);
    final top = tester.getTopLeft(column).dy;
    final right = tester.getTopLeft(column).dx;

    // The chip comes on its own, from the camera coming to rest over an
    // area not downloaded; the screen around it builds again later, for a
    // change of its own (another profile), and measures its chrome then.
    harness.stopsCoverage.changed((_) => false);
    for (final listener in [...h.map.cameraIdleListeners]) {
      listener();
    }
    await tester.pumpAndSettle();
    final chip = find.text(l10n.searchAreaNotDownloaded);
    expect(chip, findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    container
        .read(plannerControllerProvider.notifier)
        .setProfile(RouteProfile.gravel);
    await tester.pumpAndSettle();
    expect(chip, findsOneWidget);
    expect(tester.getTopLeft(column).dy, top);
    // Beside it, not over it.
    expect(
      tester.getRect(find.byType(StopsDownloadChip)).right,
      lessThan(right),
    );

    harness.stopsCoverage.changed((_) => true);
    await tester.pumpAndSettle();
    expect(chip, findsNothing);
    expect(tester.getTopLeft(column).dy, top);
  });

  testWidgets('Plan: with no layer on, an area not downloaded is said too, '
      'and goes once it is', (tester) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    h.map
      ..zoom = 13
      ..center = const LatLng(48.05, 11.05)
      ..visibleBounds = const BoundingBox(
        south: 48.0,
        west: 11.0,
        north: 48.1,
        east: 11.1,
      );
    for (final listener in [...h.map.cameraIdleListeners]) {
      listener();
    }
    await tester.pumpAndSettle();
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);
    expect(find.text(l10n.mapStopsNotDownloaded), findsNothing);
    expectNoClippedText(tester);

    // The whole chip opens the download.
    await tester.tap(find.text(l10n.searchAreaNotDownloaded));
    await tester.pumpAndSettle();
    expect(find.byType(OfflineScreen), findsOneWidget);
    await tapBack(tester);

    harness.stopsCoverage.changed((_) => true);
    await tester.pumpAndSettle();
    expect(find.text(l10n.searchAreaNotDownloaded), findsNothing);
  });

  testWidgets('Plan: the area hint closes for its area, stays closed while '
      'the map is over it and comes back over another', (tester) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    Future<void> lookAt(double lon, double lat) async {
      h.map
        ..zoom = 13
        ..center = LatLng(lat, lon)
        ..visibleBounds = BoundingBox(
          south: lat - 0.05,
          west: lon - 0.05,
          north: lat + 0.05,
          east: lon + 0.05,
        );
      for (final listener in [...h.map.cameraIdleListeners]) {
        listener();
      }
      await tester.pumpAndSettle();
    }

    await lookAt(11.05, 48.05);
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);
    expect(find.byTooltip(l10n.mapAreaHintHide), findsOneWidget);
    expectNoClippedText(tester);

    // The download is still the rest of the chip.
    await tester.tap(find.text(l10n.mapStopsDownload));
    await tester.pumpAndSettle();
    expect(find.byType(OfflineScreen), findsOneWidget);
    await tapBack(tester);
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.mapAreaHintHide));
    await tester.pumpAndSettle();
    expect(find.text(l10n.searchAreaNotDownloaded), findsNothing);
    expect(find.byType(OfflineScreen), findsNothing);

    // Panned within the same downloadable area: still closed.
    await lookAt(13.8, 46.2);
    expect(find.text(l10n.searchAreaNotDownloaded), findsNothing);

    // Into another area not downloaded: back.
    await lookAt(16.4, 48.2);
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);
  });

  testWidgets('Plan: the stops chip closes for its area with the area hint, '
      'stays closed while the map is over it and comes back over another', (
    tester,
  ) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
      extraOverrides: [
        mapStopsFinderProvider.overrideWithValue(
          (box, kinds, limit, {ranked = false}) async => const <SearchResult>[],
        ),
      ],
    );
    await ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
        .read(mapStopsPreferencesProvider.notifier)
        .setShown(true);
    Future<void> lookAt(double lon, double lat) async {
      h.map
        ..zoom = 13
        ..center = LatLng(lat, lon)
        ..visibleBounds = BoundingBox(
          south: lat - 0.05,
          west: lon - 0.05,
          north: lat + 0.05,
          east: lon + 0.05,
        );
      for (final listener in [...h.map.cameraIdleListeners]) {
        listener();
      }
      await tester.pump(stopsDebounce * 2);
      await tester.pumpAndSettle();
    }

    await lookAt(11.05, 48.05);
    expect(find.text(l10n.mapStopsNotDownloaded), findsOneWidget);
    expect(find.byTooltip(l10n.mapAreaHintHide), findsOneWidget);
    expectNoClippedText(tester);

    await tester.tap(find.text(l10n.mapStopsDownload));
    await tester.pumpAndSettle();
    expect(find.byType(OfflineScreen), findsOneWidget);
    await tapBack(tester);

    await tester.tap(find.byTooltip(l10n.mapAreaHintHide));
    await tester.pumpAndSettle();
    expect(find.byType(OfflineScreen), findsNothing);
    // No other chip about the same area takes its place.
    expect(find.text(l10n.mapStopsNotDownloaded), findsNothing);
    expect(find.text(l10n.searchAreaNotDownloaded), findsNothing);

    // Panned within the same downloadable area: still closed.
    await lookAt(13.8, 46.2);
    expect(find.text(l10n.mapStopsNotDownloaded), findsNothing);

    // Into another area not downloaded: back.
    await lookAt(16.4, 48.2);
    expect(find.text(l10n.mapStopsNotDownloaded), findsOneWidget);
    expect(find.byTooltip(l10n.mapAreaHintHide), findsOneWidget);

    // Downloaded: gone as before.
    harness.stopsCoverage.changed((_) => true);
    await tester.pump(stopsDebounce * 2);
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapStopsNotDownloaded), findsNothing);
  });

  testWidgets('Plan: the cycle map chip closes for its area and comes back '
      'over another', (tester) async {
    await pumpScreen(
      tester,
      const PlannerScreen(),
      surfaceSize: const Size(360, 780),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    final missing = container.read(sharedCycleMapMissingAreaProvider.notifier);
    Future<void> over(TileName? area) async {
      missing.set(area);
      await tester.pumpAndSettle();
    }

    await over(const TileName(10, 45));
    expect(find.text(l10n.mapCycleMapNotDownloaded), findsOneWidget);
    expect(find.byTooltip(l10n.mapAreaHintHide), findsOneWidget);
    expectNoClippedText(tester);

    await tester.tap(find.text(l10n.mapStopsDownload));
    await tester.pumpAndSettle();
    expect(find.byType(OfflineScreen), findsOneWidget);
    await tapBack(tester);

    await tester.tap(find.byTooltip(l10n.mapAreaHintHide));
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapCycleMapNotDownloaded), findsNothing);
    expect(
      container.read(areaHintDismissalsProvider),
      contains(const TileName(10, 45)),
    );

    // Out of the area and back into it: still closed.
    await over(null);
    await over(const TileName(10, 45));
    expect(find.text(l10n.mapCycleMapNotDownloaded), findsNothing);

    // Over another area not downloaded: back.
    await over(const TileName(15, 45));
    expect(find.text(l10n.mapCycleMapNotDownloaded), findsOneWidget);
    expect(find.byTooltip(l10n.mapAreaHintHide), findsOneWidget);

    // Downloaded: gone.
    await over(null);
    expect(find.text(l10n.mapCycleMapNotDownloaded), findsNothing);
  });

  testWidgets('Record: along a route with nothing ahead downloaded, the chip '
      'stands where the stops ahead would, and opens the download', (
    tester,
  ) async {
    const mPerLon = 111195 * 0.66913;
    final line = <LatLng>[
      for (var m = 0.0; m <= 20000; m += 500) LatLng(48, 11 + m / mPerLon),
    ];
    final harness = RecordingHarness();
    harness.planner.stopsCoverage.covered = (_) => false;
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
      preferences: const <String, Object>{'map.stops.shown': true},
      extraOverrides: [
        activeGuidedRouteProvider.overrideWithValue(
          GuidedRoute(key: 'r1', line: line, turns: const []),
        ),
        mapStopsFinderProvider.overrideWithValue(
          (box, kinds, limit, {ranked = false}) async => const <SearchResult>[],
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.mapStopsNotDownloaded), findsOneWidget);
    expect(find.byType(StopsAheadLine), findsNothing);
    expectNoClippedText(tester);

    await tester.tap(find.text(l10n.mapStopsDownload));
    await tester.pumpAndSettle();
    expect(find.byType(OfflineScreen), findsOneWidget);
    await tapBack(tester);

    harness.planner.stopsCoverage.changed((_) => true);
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapStopsNotDownloaded), findsNothing);
    expect(find.byType(StopsAheadLine), findsOneWidget);
  });

  testWidgets('Record: the stops chip closes for the area the rider is in, '
      'and is not closed by closing another', (tester) async {
    const mPerLon = 111195 * 0.66913;
    final line = <LatLng>[
      for (var m = 0.0; m <= 20000; m += 500) LatLng(48, 11 + m / mPerLon),
    ];
    final harness = RecordingHarness();
    harness.planner.stopsCoverage.covered = (_) => false;
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
      preferences: const <String, Object>{'map.stops.shown': true},
      extraOverrides: [
        activeGuidedRouteProvider.overrideWithValue(
          GuidedRoute(key: 'r1', line: line, turns: const []),
        ),
        mapStopsFinderProvider.overrideWithValue(
          (box, kinds, limit, {ranked = false}) async => const <SearchResult>[],
        ),
      ],
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecordingScreen)),
    );

    // Closed over another area: still here.
    container
        .read(areaHintDismissalsProvider.notifier)
        .dismiss(const TileName(15, 45));
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapStopsNotDownloaded), findsOneWidget);
    expect(find.byTooltip(l10n.mapAreaHintHide), findsOneWidget);
    expectNoClippedText(tester);

    await tester.tap(find.byTooltip(l10n.mapAreaHintHide));
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapStopsNotDownloaded), findsNothing);
    expect(find.byType(StopsAheadLine), findsNothing);
    expect(find.byType(OfflineScreen), findsNothing);
    expect(
      container.read(areaHintDismissalsProvider),
      contains(const TileName(10, 45)),
    );
  });
}
