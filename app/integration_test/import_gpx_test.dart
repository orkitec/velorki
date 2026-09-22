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
import 'package:velorki/features/planner/presentation/route_stats_row.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import 'support/harness.dart';
import 'support/region.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('imports a GPX file and saves it to the library', (tester) async {
    final container = await pumpApp(tester);
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
