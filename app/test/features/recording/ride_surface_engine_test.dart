// The surface match against the real on-device engine and a real tile: a
// recorded track is thinned, routed with `shortest` and read back as surface
// statistics. Skipped unless `BROUTER_SEGMENTS_DIR` holds the Madeira tile the
// oracle uses (`tools/brouter-oracle/tiles/W20_N30.rd5`), the same switch the
// routing package's own engine tests are behind.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/ride_stats.dart';
import 'package:velorki/features/recording/application/ride_surface.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

final String? _segmentsDir = Platform.environment['BROUTER_SEGMENTS_DIR'];
final String _profilesDir =
    Platform.environment['BROUTER_PROFILES_DIR'] ?? '../brouter/profiles';
const String _corpus = '../tools/brouter-oracle/corpus/responses';

String? get _skip {
  final dir = _segmentsDir;
  if (dir == null) return 'BROUTER_SEGMENTS_DIR is not set';
  if (!File('$dir/W20_N30.rd5').existsSync()) return 'W20_N30.rd5 not in $dir';
  if (!File('$_profilesDir/lookups.dat').existsSync()) {
    return 'lookups.dat not in $_profilesDir';
  }
  if (!File('$_corpus/pair-000.geojson').existsSync()) {
    return 'oracle corpus not found';
  }
  return null;
}

/// A ride that followed the oracle's route [id] exactly, fixed every few
/// metres at 18 km/h, so the recorded distance is the route's length.
Ride _rideAlong(String id) {
  final geo = jsonDecode(
    File('$_corpus/$id.geojson').readAsStringSync(),
  ) as Map<String, dynamic>;
  final feature = (geo['features'] as List).first as Map<String, dynamic>;
  final coords = (feature['geometry'] as Map)['coordinates'] as List;
  final start = DateTime.utc(2026, 9, 21, 9);
  final points = <TrackPoint>[];
  var distance = 0.0;
  LatLng? last;
  for (final c in coords) {
    final list = c as List;
    final pos = LatLng(
      (list[1] as num).toDouble(),
      (list[0] as num).toDouble(),
    );
    if (last != null) distance += haversineMeters(last, pos);
    last = pos;
    points.add(
      TrackPoint(
        pos,
        ele: (list[2] as num).toDouble(),
        time: start.add(Duration(milliseconds: (distance / 5 * 1000).round())),
      ),
    );
  }
  return Ride(
    id: id,
    name: id,
    startedAt: start,
    endedAt: points.last.time!,
    stats: RideStats(
      distanceM: distance,
      movingTime: points.last.time!.difference(start),
    ),
    geometry: PackedTrack.encode(points),
  );
}

void main() {
  late LocalRoutingBackend local;
  late RideSurfaceService service;

  setUpAll(() {
    if (_skip != null) return;
    local = LocalRoutingBackend(
      segmentsDir: _segmentsDir!,
      profilesDir: _profilesDir,
    );
    final composite = CompositeRoutingBackend(
      local: local,
      localTiles: local.availableTiles,
    );
    service = RideSurfaceService(local: local, decide: composite.decide);
  });
  tearDownAll(() async {
    if (_skip == null) await local.dispose();
  });

  test(
    'a ride along a routed track is matched and read as surfaces, with '
    'the tags a shortest route would otherwise drop',
    () async {
      for (final id in const ['pair-000', 'pair-002', 'pair-004', 'pair-008']) {
        final ride = _rideAlong(id);
        final result = await service.match(ride);
        // ignore: avoid_print
        print(
          '$id: ${ride.stats.distanceM.round()} m ridden → ${result.state}; '
          '${result.stats}',
        );
        expect(result.state, RideSurfaceState.matched, reason: id);
        final stats = result.stats!;
        expect(stats.coveredLengthM, greaterThan(0), reason: id);
        expect(
          stats.pavedShare + stats.unpavedShare + stats.unknownShare,
          closeTo(1, 0.02),
          reason: id,
        );
      }
    },
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
