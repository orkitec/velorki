import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/map/application/map_stops_controller.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/presentation/stops_ahead_line.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/search_field.dart'
    show gazetteerPoiKindLabel;
import 'package:velorki/features/shared/application/active_tab.dart';
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
        mapStopsFinderProvider.overrideWithValue((box, kinds, limit) async {
          asked.add(box);
          return [fountain];
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

    expect(asked, <BoundingBox>[view]);
    expect(h.map.stops.single.name, 'Brunnen');

    h.map.onStopTapped!(0);
    await tester.pumpAndSettle();
    // Pinned and offered, as a place picked from the search is.
    expect(h.map.searchPin, fountain.position);
    expect(find.text(l10n.plannerSetAsStart), findsOneWidget);

    container.read(activeTabProvider.notifier).show(recordingRoute);
    await tester.pumpAndSettle();
    expect(h.map.stops, isEmpty);
    expect(h.map.onStopTapped, isNull);
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
          (box, kinds, limit) async => [
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

    h.map.onStopTapped!(1);
    await tester.pumpAndSettle();
    expect(
      find.text(
        l10n.mapStopNamed('Café Rad', gazetteerPoiKindLabel(l10n, 'cafe')!),
      ),
      findsOneWidget,
    );
    expect(h.map.stops[1].selected, isTrue);
  });
}
