// A GPX file arrives the way a shared or opened file does, and the rider saves
// it into the library.
//
//   flutter test integration_test/import_gpx_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL=
//
// The file is handed to the real IncomingFileService with `addBytes`, which is
// the same sink the share sheet, the "open with" intent and the file picker
// all end up in; only the platform channels below it are skipped. Everything
// above — decoding, the preview screen, saving, the library — is the real
// thing.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/import_export/application/incoming_import_listener.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/presentation/route_stats_row.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('imports a GPX file and saves it to the library', (tester) async {
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
    // bootstrap() attaches this; a test that builds its own container has to
    // do it itself, or nothing ever navigates to the preview.
    listenForIncomingImports(container);

    final name = 'Itest import ${DateTime.now().millisecondsSinceEpoch}';
    final gpx = GpxCodec.encodeRoute(points: _trackPoints(), name: name);
    final bytes = Uint8List.fromList(utf8.encode(gpx));

    await container
        .read(incomingFileServiceProvider)
        .addBytes(bytes, fileName: '$name.gpx', sourceHint: 'picker');
    // _open defers the navigation into a post-frame callback.
    await pumpFor(tester, const Duration(milliseconds: 500));

    await waitForWidget(tester, find.widgetWithText(AppBar, 'Import'));
    expect(find.text('GPX · ${_trackPoints().length} points'), findsOneWidget);

    await waitForWidget(tester, find.byType(RouteStatsRow));
    final stats = tester.widget<RouteStatsRow>(find.byType(RouteStatsRow));
    debugPrint(
      'VELORKI_IMPORT distance=${stats.distanceM.round()}m '
      'ascent=${stats.ascentM.round()}m',
    );
    expect(stats.distanceM, greaterThan(0));
    expect(find.text('DISTANCE'), findsWidgets);

    await screenshot(tester, 'import-preview');

    // savedRoutesProvider is autoDispose: a bare `read` would build the stream
    // and tear it down again before it ever emits, so keep it subscribed.
    final routes = container.listen(savedRoutesProvider, (_, _) {});
    addTearDown(routes.close);

    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Save'));

    // Saving lands on the route's card on the Library tab, its name in the
    // card's header with the back arrow; the row is in the list behind it.
    await waitUntil(
      tester,
      () => routes.read().value?.any((route) => route.name == name) ?? false,
      describe: 'the imported route in the library',
      onTimeout: () => '${routes.read()}',
    );
    await waitForWidget(tester, find.byType(BackButton));
    await waitForWidget(tester, find.text(name));

    // The Library tab again pops the card back to the list.
    await tapAndPump(tester, find.text('Library'));
    // The Library remembers its last segment across launches, and another
    // test may have left it on the rides; this one wants the routes.
    await tapAndPump(tester, find.text('Routes'));
    await waitForWidget(tester, find.widgetWithText(ListTile, name));

    await unmountApp(tester);
  });

  testWidgets('a GPX track without turns gets them from the map', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      overrides: [
        recordingRecoveryProvider.overrideWith(
          (ref) async => const NoRecovery(),
        ),
      ],
    );
    listenForIncomingImports(container);
    await ensureRegionTile(tester, container);

    // A line on the region's streets, as the router draws it, written out
    // with no cue sheet: what a plain track file is.
    final backend = container.read(routingBackendProvider);
    expect(backend, isNotNull, reason: 'no on-device routing');
    final routed = await backend!.route(
      RouteQuery(points: <LatLng>[region.start, region.via]),
    );
    final points = routed.geometry;
    final name = 'Itest turns ${DateTime.now().millisecondsSinceEpoch}';
    final gpx = GpxCodec.encodeRoute(points: points, name: name);
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
    await waitForWidget(tester, find.byType(RouteStatsRow));
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Save'));

    // In the background, without a word: the turns arrive on the route.
    await waitUntil(
      tester,
      () =>
          routes.read().value?.any(
            (route) => route.name == name && route.turnsGenerated,
          ) ??
          false,
      describe: 'turns made from the map for the imported track',
      timeout: const Duration(minutes: 2),
    );
    final saved = routes.read().value!.firstWhere((r) => r.name == name);
    final turns = saved.turns.where((t) => t.kind != TurnKind.end).toList();
    debugPrint(
      'VELORKI_TURNS made=${turns.length} router=${routed.turns.length} '
      'points=${points.length}',
    );
    expect(turns, isNotEmpty);
    expect(saved.geometry, hasLength(points.length), reason: 'line unchanged');

    // The card's cue sheet says where they came from.
    final note = find.text('Turns created from the map');
    await waitUntil(
      tester,
      () => note.evaluate().isNotEmpty,
      describe: 'the note under the cue sheet',
    );
    await tester.ensureVisible(note);
    await pumpFor(tester, const Duration(milliseconds: 300));
    await screenshot(tester, 'import-turns-from-map');

    await unmountApp(tester);
  });
}

/// A short track inside the region's rd5 tile, with a little climbing so the
/// ascent stat is not zero either.
List<TrackPoint> _trackPoints() {
  final start = region.start;
  return List<TrackPoint>.generate(
    12,
    (i) => TrackPoint(
      LatLng(start.lat + i * 0.0009, start.lon + i * 0.0011),
      ele: 20 + (i % 4) * 6.0,
    ),
    growable: false,
  );
}
