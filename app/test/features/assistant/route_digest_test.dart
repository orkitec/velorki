// The route digest: the builder over synthetic lines, and the whole service
// over the oracle's Madeira tile and its gazetteer, both committed.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart' show RouteSource;
import 'package:velorki/core/geo/track_surface.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/domain/route_digest_builder.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

const String _tiles = '../tools/brouter-oracle/tiles';
const String _profiles = '../brouter/profiles';
const String _gazetteers = '../tools/gazetteer/fixtures';

/// Metres per degree of longitude on the equator, where the test lines run.
final double _mPerDeg = earthRadiusMeters * math.pi / 180;

/// A line due east along the equator, a point every 10 m, [lengthM] long,
/// with the height [ele] gives at every distance.
List<TrackPoint> _line(double lengthM, {double Function(double d)? ele}) => [
  for (var d = 0.0; d <= lengthM + 1e-6; d += 10)
    TrackPoint(LatLng(0, d / _mPerDeg), ele: ele?.call(d) ?? 0),
];

/// The point [d] metres along [_line], and [off] metres north of it.
LatLng _at(double d, {double off = 0}) => LatLng(off / _mPerDeg, d / _mPerDeg);

/// One router message: [lengthM] of way with [tags].
SegmentMessage _way(double lengthM, Map<String, String> tags) => SegmentMessage(
  position: const LatLng(0, 0),
  elevationM: 0,
  distanceM: lengthM,
  costPerKm: 0,
  elevCost: 0,
  turnCost: 0,
  nodeCost: 0,
  initialCost: 0,
  wayTags: tags,
  nodeTags: const <String, String>{},
  timeS: 0,
  energyJ: 0,
);

const Map<String, String> _cycleway = <String, String>{
  'highway': 'cycleway',
  'surface': 'asphalt',
};
const Map<String, String> _residential = <String, String>{
  'highway': 'residential',
  'surface': 'asphalt',
};
const Map<String, String> _track = <String, String>{
  'highway': 'track',
  'surface': 'gravel',
};

void _expectContiguous(
  List<DigestStretch> stretches,
  double lengthKm, {
  double within = 0.01,
}) {
  expect(stretches.first.fromKm, 0);
  expect(stretches.last.toKm, closeTo(lengthKm, within));
  for (var i = 1; i < stretches.length; i++) {
    expect(stretches[i].fromKm, stretches[i - 1].toKm);
  }
}

void main() {
  group('stretches', () {
    test('split where the road or the surface changes, and a bit shorter '
        'than 300 m joins its neighbours', () {
      final digest = buildRouteDigest(
        geometry: _line(6000),
        messages: [
          _way(2000, _cycleway),
          _way(100, _residential),
          _way(1900, _cycleway),
          _way(2000, _track),
        ],
      );
      expect(digest.stretches, hasLength(2));
      final [paved, gravel] = digest.stretches;
      expect(paved.road, 'cycleway');
      expect(paved.surface, 'asphalt');
      expect(paved.toKm, closeTo(4, 0.03));
      expect(gravel.road, 'track');
      expect(gravel.surface, 'gravel');
      expect(paved.start, const DigestPoint(lat: 0, lon: 0));
      expect(gravel.end.lon, closeTo(6000 / _mPerDeg, 1e-5));
      _expectContiguous(digest.stretches, 6);
    });

    test('split where the gradient changes, with its average and steepest '
        'grade', () {
      // Flat for 2 km, 8 % for 1 km, flat again for 2 km.
      double ele(double d) => d < 2000
          ? 0
          : d < 3000
          ? (d - 2000) * 0.08
          : 80;
      final digest = buildRouteDigest(
        geometry: _line(5000, ele: ele),
        messages: [_way(5000, _cycleway)],
      );
      expect(digest.stretches, hasLength(3));
      final climb = digest.stretches[1];
      expect(climb.fromKm, closeTo(2, 0.1));
      expect(climb.toKm, closeTo(3, 0.1));
      expect(climb.avgGrade, closeTo(8, 1));
      expect(climb.maxGrade, closeTo(8, 0.5));
      expect(digest.stretches.first.avgGrade, closeTo(0, 0.5));
      _expectContiguous(digest.stretches, 5);
    });

    test('never more than 60, however often the way changes', () {
      // 80 km of ways between 150 and 900 m long, of four kinds in no order.
      final random = math.Random(7);
      const kinds = <Map<String, String>>[
        _cycleway,
        _residential,
        _track,
        <String, String>{'highway': 'tertiary', 'surface': 'asphalt'},
      ];
      final ways = <SegmentMessage>[];
      var total = 0.0;
      while (total < 80000) {
        final length = math.min(150 + random.nextDouble() * 750, 80000 - total);
        ways.add(_way(length, kinds[random.nextInt(kinds.length)]));
        total += length;
      }
      final digest = buildRouteDigest(geometry: _line(80000), messages: ways);
      expect(digest.stretches.length, lessThanOrEqualTo(digestMaxStretches));
      expect(digest.stretches.length, greaterThanOrEqualTo(20));
      _expectContiguous(digest.stretches, 80);
    });

    test('a route with no messages has none, and still its climbs', () {
      final digest = buildRouteDigest(
        geometry: _line(3000, ele: (d) => d * 0.05),
      );
      expect(digest.stretches, isEmpty);
      expect(digest.climbs, hasLength(1));
    });
  });

  group('climbs', () {
    test('a climb is found where it is, with its gain and gradients', () {
      double ele(double d) => d < 2000
          ? 0
          : d < 3000
          ? (d - 2000) * 0.08
          : 80;
      final [climb] = buildRouteDigest(geometry: _line(5000, ele: ele)).climbs;
      expect(climb.startKm, closeTo(2, 0.1));
      expect(climb.lengthKm, closeTo(1, 0.15));
      expect(climb.gainM, closeTo(80, 3));
      expect(climb.avgGrade, closeTo(8, 1));
      expect(climb.maxGrade, closeTo(8, 0.5));
    });

    test('too little gain or too gentle a gradient is no climb', () {
      // 30 m at 6 %.
      expect(
        buildRouteDigest(
          geometry: _line(2000, ele: (d) => d.clamp(500, 1000) * 0.06),
        ).climbs,
        isEmpty,
      );
      // 60 m over 3 km, 2 %.
      expect(
        buildRouteDigest(geometry: _line(3000, ele: (d) => d * 0.02)).climbs,
        isEmpty,
      );
    });

    test('a descent between two climbs splits them', () {
      // Up 100 m, down 100 m, up 100 m, each over 1 km.
      double ele(double d) => switch (d) {
        < 1000 => d * 0.1,
        < 2000 => 100 - (d - 1000) * 0.1,
        _ => (d - 2000) * 0.1,
      };
      final climbs = buildRouteDigest(geometry: _line(3000, ele: ele)).climbs;
      expect(climbs, hasLength(2));
      expect(climbs[1].startKm, closeTo(2, 0.1));
    });
  });

  group('towns and places', () {
    test(
      'a settlement counts within its reach of the line, in route order',
      () {
        final digest = buildRouteDigest(
          geometry: _line(10000),
          candidates: [
            DigestCandidate(
              name: 'Far',
              kind: 'village',
              position: _at(2000, off: 800),
            ),
            DigestCandidate(
              name: 'Big',
              kind: 'city',
              position: _at(8000, off: 1500),
            ),
            DigestCandidate(
              name: 'Near',
              kind: 'village',
              position: _at(3000, off: 400),
            ),
            DigestCandidate(name: 'Small', kind: 'hamlet', position: _at(5000)),
          ],
        );
        expect([for (final t in digest.towns) t.name], ['Near', 'Big']);
        expect(digest.towns.first.km, closeTo(3, 0.05));
        expect(digest.towns.last.kind, 'city');
      },
    );

    test('a place within 300 m is kept with its km and distance off, '
        'twins and other kinds are not', () {
      final digest = buildRouteDigest(
        geometry: _line(10000),
        candidates: [
          DigestCandidate(
            name: 'Café Uno',
            kind: 'cafe',
            position: _at(4000, off: 100),
          ),
          // The same café mapped twice.
          DigestCandidate(
            name: 'Café Uno',
            kind: 'cafe',
            position: _at(4050, off: 120),
          ),
          DigestCandidate(
            name: '',
            kind: 'drinking_water',
            position: _at(1000, off: 20),
          ),
          DigestCandidate(
            name: 'Too far',
            kind: 'cafe',
            position: _at(6000, off: 500),
          ),
          DigestCandidate(name: 'Hotel', kind: 'hotel', position: _at(7000)),
        ],
      );
      expect(digest.places, hasLength(2));
      final [water, cafe] = digest.places;
      expect(water.id, 'p1');
      expect(water.kind, 'drinking_water');
      expect(water.name, isNull);
      expect(water.offM, closeTo(20, 1));
      expect(cafe.id, 'p2');
      expect(cafe.name, 'Café Uno');
      expect(cafe.km, closeTo(4, 0.05));
      expect(cafe.offM, closeTo(100, 1));
    });

    test('at most 40 places, spread along the route and across kinds', () {
      final candidates = <DigestCandidate>[
        // 150 cafés crowded into the first 3 km…
        for (var i = 0; i < 150; i++)
          DigestCandidate(
            name: 'Café $i',
            kind: 'cafe',
            position: _at(i * 20.0, off: 50 + (i % 5) * 40),
          ),
        // …and a tap every 2 km along the whole 40.
        for (var d = 1000.0; d < 40000; d += 2000)
          DigestCandidate(name: '', kind: 'drinking_water', position: _at(d)),
      ];
      final digest = buildRouteDigest(
        geometry: _line(40000),
        candidates: candidates,
      );
      expect(digest.places, hasLength(digestMaxPlaces));
      expect(
        digest.places.where((p) => p.kind == 'drinking_water'),
        hasLength(20),
      );
      expect(digest.places.last.km, greaterThan(35));
      expect(
        [for (final p in digest.places) p.id],
        [for (var i = 1; i <= digestMaxPlaces; i++) 'p$i'],
      );
      final kms = [for (final p in digest.places) p.km];
      expect(kms, [...kms]..sort());
    });

    test('a loop is a route that ends where it starts', () {
      final out = _line(3000);
      final loop = [...out, ...out.reversed.skip(1)];
      expect(buildRouteDigest(geometry: loop).loop, isTrue);
      expect(buildRouteDigest(geometry: out).loop, isFalse);
    });
  });

  group('on Madeira', () {
    late LocalRoutingBackend local;
    late GazetteerStore gazetteer;
    late RouteDigestService service;

    setUpAll(() async {
      local = LocalRoutingBackend(segmentsDir: _tiles, profilesDir: _profiles);
      final composite = CompositeRoutingBackend(
        local: local,
        localTiles: local.availableTiles,
      );
      gazetteer = GazetteerStore(Directory(_gazetteers));
      await gazetteer.refresh();
      service = RouteDigestService(
        surfaces: TrackSurfaceService(local: local, decide: composite.decide),
        gazetteer: () async => gazetteer,
      );
    });
    tearDownAll(() async {
      gazetteer.close();
      await local.dispose();
    });

    test('a ride from Funchal to Machico is told by its roads, climbs, '
        'towns and stops', () async {
      const stops = <LatLng>[
        LatLng(32.6475, -16.9087), // Funchal
        LatLng(32.6667, -16.8456), // Camacha
        LatLng(32.6875, -16.7917), // Santa Cruz
        LatLng(32.7167, -16.7667), // Machico
      ];
      final result = await local.route(
        const RouteQuery(points: stops, profile: 'velorki-trekking'),
      );
      final route = SavedRoute(
        id: 'madeira',
        name: 'Funchal to Machico',
        source: RouteSource.planned,
        profile: RouteProfile.trekking,
        createdAt: DateTime(2026, 10),
        updatedAt: DateTime(2026, 10),
        distanceM: result.lengthM,
        ascentM: result.ascentM,
        descentM: result.descentM,
        bounds: result.bounds!,
        geometryBlob: PackedTrack.encode(result.geometry),
        waypoints: [for (final p in stops) Waypoint(pos: p)],
        options: const RoutingOptions(),
      );

      final digest = (await service.digestOf(route))!;
      final lengthKm = result.lengthM / 1000;

      expect(digest.profile, 'trekking');
      expect(digest.loop, isFalse);
      expect(digest.stretches, isNotEmpty);
      expect(digest.stretches.length, lessThanOrEqualTo(digestMaxStretches));
      _expectContiguous(digest.stretches, lengthKm, within: 0.3);
      expect(
        digest.stretches.every((s) => s.road != 'unknown'),
        isTrue,
        reason: '${digest.stretches}',
      );
      expect(digest.climbs, isNotEmpty);
      expect(
        digest.climbs.every((c) => c.gainM >= digestClimbMinGainM),
        isTrue,
      );
      final towns = [for (final t in digest.towns) t.name];
      expect(towns, contains('Funchal'));
      expect(towns, contains('Machico'));
      expect(digest.places, isNotEmpty);
      expect(digest.places.length, lessThanOrEqualTo(digestMaxPlaces));
      expect(
        digest.places.every(
          (p) => p.offM <= digestPlaceReachM && p.km <= lengthKm + 0.1,
        ),
        isTrue,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
