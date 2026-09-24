// TEMPORARY probe, delete after looking at the screenshots.
//
// The discs sized to their glyphs: the three widest of the sixteen side by
// side, the middle one chosen, so the ring can be read off the picture.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/presentation/poi_markers.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

const EdgeInsets _above = EdgeInsets.only(top: 150, bottom: 400);

Future<void> _pose(WidgetTester tester, String name) async {
  debugPrint('VELORKI_PROBE $name');
  await pumpFor(tester, const Duration(seconds: 14));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('discs sized to their glyphs', (tester) async {
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
    await container
        .read(appearanceSettingProvider.notifier)
        .setMode(ThemeMode.light);

    final planner = container.read(plannerControllerProvider.notifier);
    planner
      ..addWaypoint(region.start)
      ..addWaypoint(region.via)
      ..addWaypoint(region.end);
    await waitUntil(
      tester,
      () {
        final state = container.read(plannerControllerProvider);
        return state.result != null && !state.isRouting;
      },
      describe: 'the route',
      timeout: const Duration(seconds: 60),
      onTimeout: () => '${container.read(plannerControllerProvider).error}',
    );
    planner.addPoi(
      LatLng(region.via.lat + 0.0008, region.via.lon + 0.0008),
      name: 'Fonte',
      kind: PoiKind.water,
    );
    await pumpFor(tester, const Duration(milliseconds: 800));

    final map = container.read(
      sharedMapControllerProvider,
    ) as MaplibreMapControllerAdapter;
    await map.moveTo(region.via, zoom: 15, animate: false, padding: _above);
    await _pose(tester, 'a-a-place-and-a-numbered-stop');

    const kinds = <PoiKind>[
      PoiKind.accommodation,
      PoiKind.repair,
      PoiKind.firstAid,
    ];
    final row = LatLng(region.via.lat + 0.002, region.via.lon - 0.004);
    await map.setPois(<MapPoi>[
      for (final (i, kind) in kinds.indexed)
        ...poiMarkers([
          RoutePoi(
            pos: LatLng(row.lat, row.lon + i * 0.0005),
            name: '',
            kind: kind,
          ),
        ], selected: i == 1 ? 0 : null),
    ]);
    await map.moveTo(
      LatLng(row.lat, row.lon + 0.0005),
      zoom: 17,
      animate: false,
      padding: _above,
    );
    await _pose(tester, 'b-the-widest-glyphs');

    await container
        .read(appearanceSettingProvider.notifier)
        .setMode(ThemeMode.system);
    await unmountApp(tester);
  });
}
