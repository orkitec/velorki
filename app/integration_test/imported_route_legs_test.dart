// An imported route keeps the file's line wherever the rider did not change
// it, against the real on-device router.
//
//   flutter test integration_test/imported_route_legs_test.dart \
//     -d <device> --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_API_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://127.0.0.1:8000 \
//     --dart-define=VELORKI_ITEST_REGION=madeira
//
// A GPX file with named points on its track arrives the way a shared file
// does and is saved; opened in the planner it has a marker at each named
// point and the file's line between them. One marker is moved: the two legs
// beside it are routed on the device, and every other stretch of the line
// has to stay the file's, point for point, through a Save and a reopen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/import_export/application/incoming_import_listener.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/planner/domain/route_legs.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('moving one marker of an imported route routes only its two '
      'legs, and the rest stays the file\'s line through a save', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      overrides: [
        // Whatever an earlier test on this device left of a ride is not
        // this test's business: the file opens at once.
        recordingRecoveryProvider.overrideWith(
          (ref) async => const NoRecovery(),
        ),
      ],
    );
    listenForIncomingImports(container);
    await ensureRegionTile(tester, container);

    final track = _track();
    final name = 'Itest legs ${DateTime.now().millisecondsSinceEpoch}';
    final gpx = GpxCodec.encodeRoute(
      points: track,
      name: name,
      waypoints: [
        GpxWaypoint(track[20].pos, name: 'Bakery'),
        GpxWaypoint(track[40].pos, name: 'Fountain'),
      ],
    );
    final routes = container.listen(savedRoutesProvider, (_, _) {});
    addTearDown(routes.close);

    await container
        .read(incomingFileServiceProvider)
        .addBytes(
          Uint8List.fromList(utf8.encode(gpx)),
          fileName: '$name.gpx',
          sourceHint: 'picker',
        );
    await pumpFor(tester, const Duration(milliseconds: 500));
    await waitForWidget(tester, find.widgetWithText(AppBar, 'Import'));
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Save'));
    await waitUntil(
      tester,
      () => routes.read().value?.any((route) => route.name == name) ?? false,
      describe: 'the imported route in the library',
      onTimeout: () => '${routes.read()}',
    );

    // ------------------------------------------------------- open in planner
    await waitForWidget(tester, find.text('Open in planner'));
    await tester.ensureVisible(find.text('Open in planner'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tapAndPump(tester, find.text('Open in planner'));
    PlannerState state() => container.read(plannerControllerProvider);
    await waitUntil(
      tester,
      () => state().savedRouteName == name,
      describe: 'the import opened in the planner',
      onTimeout: () => '${state()}',
    );
    expect(state().waypoints.map((w) => w.name), [
      null,
      'Bakery',
      'Fountain',
      null,
    ]);
    expect(state().legs.map((l) => l?.kept), [true, true, true]);
    // The file's line as it was stored, which is the line the file drew.
    final line = state().result!.geometry;
    expect(line, hasLength(track.length));

    // ------------------------------------------------------ move one marker
    final moved = LatLng(track[20].lat + 0.002, track[20].lon - 0.002);
    container.read(plannerControllerProvider.notifier).moveWaypoint(1, moved);
    await pumpFor(tester, const Duration(milliseconds: 400));
    await waitUntil(
      tester,
      () {
        final now = state();
        if (now.route.hasError) fail('routing failed: ${now.route.error}');
        return now.result != null && !now.isRouting;
      },
      describe: 'the two legs routed on the device',
      timeout: const Duration(seconds: 90),
      onTimeout: () => '${state()}',
    );

    final edited = state().result! as PlannedRoute;
    expect(state().legs.map((l) => l!.kept), [false, false, true]);
    final tail = _positions(edited.geometry.sublist(edited.legStarts[2]));
    expect(tail, _positions(line.sublist(40)));
    debugPrint(
      'VELORKI_LEGS routed ${edited.legStarts[2]} points, kept '
      '${tail.length}, length ${edited.lengthM.round()}m',
    );

    // ------------------------------------------------------- save, reopen
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tapAndPump(tester, save);
    await waitForWidget(tester, find.byType(AlertDialog));
    await tapAndPump(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Save'),
      ),
    );
    await waitUntil(
      tester,
      () => state().routeIsSaved,
      describe: 'the edited route saved',
      onTimeout: () => '${state()}',
    );

    final saved = (await container
        .read(routeRepositoryProvider)
        .routeById(state().savedRouteId!))!;
    container.read(plannerControllerProvider.notifier)
      ..clear()
      ..loadSavedRoute(saved);
    await pumpFor(tester, const Duration(milliseconds: 300));

    final reopened = state();
    expect(_positions(reopened.result!.geometry), _positions(edited.geometry));
    expect(reopened.legs.map((l) => l!.kept), [false, false, true]);
    expect(
      _positions(reopened.legs.last!.geometry),
      _positions(line.sublist(40)),
    );
    expect(_positions(saved.original!.geometry), _positions(line));

    await unmountApp(tester);
  });
}

List<LatLng> _positions(List<TrackPoint> points) => [
  for (final p in points) p.pos,
];

/// A line of 61 points, some 100 m apart, heading north-east from the
/// region's start: inside its tile, on no road in particular.
List<TrackPoint> _track() => List<TrackPoint>.generate(
  61,
  (i) => TrackPoint(
    LatLng(region.start.lat + i * 0.0008, region.start.lon + i * 0.0008),
    ele: 20 + i.toDouble(),
  ),
  growable: false,
);
