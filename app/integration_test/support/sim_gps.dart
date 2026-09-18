// The iOS simulator's GPS, driven from a test.
//
// tool/sim_ride.py keeps the simulated location moving along the region's
// straight-line route and watches the app's container for a route file; a
// test that has planned a route hands it over here, and the simulated rider
// switches to it. Nothing here does anything off the simulator.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'harness.dart';

/// Where tool/sim_ride.py looks, relative to the app's support directory.
const String simRouteFile = 'itest/route.txt';

/// Asks the runner to ride [line] on the simulator's GPS, and waits long
/// enough for it to have picked the request up and moved the position to
/// the start of it.
Future<void> rideSimulatorAlong(WidgetTester tester, List<LatLng> line) async {
  final base = await getApplicationSupportDirectory();
  final file = File(p.join(base.path, simRouteFile));
  await file.parent.create(recursive: true);
  final points = thinLine(line, 12);
  await file.writeAsString(
    points.map((point) => '${point.lat},${point.lon}').join('\n'),
  );
  // The runner polls once a second; simctl needs a moment more to issue the
  // first fix on the new path.
  await pumpFor(tester, const Duration(seconds: 5));
}

/// [line] with points closer than [everyM] to the previous kept one dropped,
/// ends kept: simctl takes the waypoints on its command line.
List<LatLng> thinLine(List<LatLng> line, double everyM) {
  if (line.length < 3) return line;
  final kept = <LatLng>[line.first];
  for (var i = 1; i < line.length - 1; i++) {
    if (haversineMeters(kept.last, line[i]) >= everyM) kept.add(line[i]);
  }
  kept.add(line.last);
  return kept;
}
