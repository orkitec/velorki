import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

import 'fake_routing_backend.dart';

const start = LatLng(48.137213, 11.575612);

RouteResult fakeRoute({
  required double lengthM,
  required String tags,
  double ascentPerKm = 10,
  FakeShape shape = FakeShape.circle,
}) => FakeRoutingBackend(
  lengthFor: (_) => lengthM,
  wayTagsFor: (_) => tags,
  ascentPerKm: ascentPerKm,
  shape: shape,
).synthesize(const RouteQuery(points: [start], roundTrip: true));

void main() {
  group('repeatedSegmentRatio', () {
    test('a loop repeats nothing', () {
      final ring = <LatLng>[
        for (var i = 0; i <= 12; i++) destinationPoint(start, i * 30.0, 5000),
      ];
      expect(RouteScorer.repeatedSegmentRatio(ring), 0);
    });

    test('a pure out and back repeats half its segments', () {
      final leg = <LatLng>[
        for (var i = 0; i <= 10; i++) destinationPoint(start, 90, i * 500.0),
      ];
      final outAndBack = <LatLng>[...leg, ...leg.reversed.skip(1)];
      expect(RouteScorer.repeatedSegmentRatio(outAndBack), closeTo(0.5, 1e-12));
    });

    test('direction does not matter', () {
      const a = LatLng(48.0, 11.0);
      const b = LatLng(48.01, 11.0);
      expect(RouteScorer.repeatedSegmentRatio([a, b, a]), closeTo(0.5, 1e-12));
    });

    test('coordinates are rounded to about 11 m before hashing', () {
      const a = LatLng(48.0, 11.0);
      const b = LatLng(48.01, 11.0);
      // 48.000001 rounds to 48.0000, so this is the same segment again.
      const aJitter = LatLng(48.000001, 11.000001);
      // Two of the three legs repeat; they are a hair shorter than the first,
      // and the ratio is measured in metres, hence the loose tolerance.
      expect(
        RouteScorer.repeatedSegmentRatio([a, b, aJitter, b]),
        closeTo(2 / 3, 1e-4),
      );
      expect(RouteScorer.repeatPrecision, 4);
    });

    test('zero-length segments are ignored', () {
      const a = LatLng(48.0, 11.0);
      const b = LatLng(48.01, 11.0);
      expect(RouteScorer.repeatedSegmentRatio([a, a, a, b]), 0);
    });

    test('degenerate inputs are zero', () {
      expect(RouteScorer.repeatedSegmentRatio(const []), 0);
      expect(RouteScorer.repeatedSegmentRatio(const [start]), 0);
      expect(RouteScorer.repeatedSegmentRatio(const [start, start]), 0);
    });

    test(
      'an out-and-back route scores worse than a loop of the same shape',
      () {
        const scorer = RouteScorer(LoopPrefs());
        final loop = scorer.score(
          fakeRoute(
            lengthM: 40000,
            tags: 'highway=residential surface=asphalt',
          ),
          targetM: 40000,
        );
        final there = scorer.score(
          fakeRoute(
            lengthM: 40000,
            tags: 'highway=residential surface=asphalt',
            shape: FakeShape.outAndBack,
          ),
          targetM: 40000,
        );
        expect(loop.features.repeatedSegmentRatio, 0);
        expect(there.features.repeatedSegmentRatio, closeTo(0.5, 1e-9));
        expect(loop.total, lessThan(there.total));
      },
    );
  });

  group('hills term', () {
    test('avoid penalises anything above 8 m/km', () {
      const s = RouteScorer(LoopPrefs(hills: Hills.avoid));
      expect(s.hillsTerm(5), 0);
      expect(s.hillsTerm(8), 0);
      expect(s.hillsTerm(28), closeTo(1, 1e-12));
      expect(s.hillsTerm(18), lessThan(s.hillsTerm(28)));
    });

    test('neutral only penalises above 15 m/km', () {
      const s = RouteScorer(LoopPrefs());
      expect(s.hillsTerm(12), 0);
      expect(s.hillsTerm(15), 0);
      expect(s.hillsTerm(35), closeTo(1, 1e-12));
    });

    test('seek rewards the 10..25 m/km band and penalises outside it', () {
      const s = RouteScorer(LoopPrefs(hills: Hills.seek));
      expect(s.hillsTerm(10), -1);
      expect(s.hillsTerm(18), -1);
      expect(s.hillsTerm(25), -1);
      expect(s.hillsTerm(0), closeTo(1, 1e-12));
      expect(s.hillsTerm(5), closeTo(0.5, 1e-12));
      expect(s.hillsTerm(45), closeTo(1, 1e-12));
    });

    test('a hilly route beats a flat one for a hill seeker and loses for an '
        'avoider', () {
      final flat = fakeRoute(
        lengthM: 40000,
        tags: 'highway=residential surface=asphalt',
        ascentPerKm: 2,
      );
      final hilly = fakeRoute(
        lengthM: 40000,
        tags: 'highway=residential surface=asphalt',
        ascentPerKm: 18,
      );
      const seeker = RouteScorer(LoopPrefs(hills: Hills.seek));
      const avoider = RouteScorer(LoopPrefs(hills: Hills.avoid));
      expect(
        seeker.score(hilly, targetM: 40000).total,
        lessThan(seeker.score(flat, targetM: 40000).total),
      );
      expect(
        avoider.score(flat, targetM: 40000).total,
        lessThan(avoider.score(hilly, targetM: 40000).total),
      );
    });
  });

  group('surface term', () {
    test('paved penalises every unpaved metre', () {
      const s = RouteScorer(LoopPrefs(surface: Surface.paved));
      expect(s.surfaceTerm(0), 0);
      expect(s.surfaceTerm(0.3), closeTo(0.3, 1e-12));
    });

    test('mixed tolerates up to 40 % unpaved', () {
      const s = RouteScorer(LoopPrefs());
      expect(s.surfaceTerm(0.3), 0);
      expect(s.surfaceTerm(0.4), 0);
      expect(s.surfaceTerm(0.9), closeTo(0.5, 1e-12));
    });

    test('gravel rewards unpaved', () {
      const s = RouteScorer(LoopPrefs(surface: Surface.gravel));
      expect(s.surfaceTerm(0.8), closeTo(-0.8, 1e-12));
    });

    test(
      'a gravel route wins for a gravel rider and loses for a road rider',
      () {
        final asphalt = fakeRoute(
          lengthM: 40000,
          tags: 'highway=residential surface=asphalt',
        );
        final gravel = fakeRoute(
          lengthM: 40000,
          tags: 'highway=track surface=gravel',
        );
        const gravelRider = RouteScorer(LoopPrefs(surface: Surface.gravel));
        const roadRider = RouteScorer(LoopPrefs(surface: Surface.paved));
        expect(
          gravelRider.score(gravel, targetM: 40000).total,
          lessThan(gravelRider.score(asphalt, targetM: 40000).total),
        );
        expect(
          roadRider.score(asphalt, targetM: 40000).total,
          lessThan(roadRider.score(gravel, targetM: 40000).total),
        );
      },
    );
  });

  group('traffic', () {
    test('avoidTraffic doubles the busy penalty', () {
      final busy = fakeRoute(
        lengthM: 40000,
        tags: 'highway=primary surface=asphalt',
      );
      const tolerant = RouteScorer(LoopPrefs(avoidTraffic: false));
      const careful = RouteScorer(LoopPrefs());
      final a = tolerant.score(busy, targetM: 40000);
      final b = careful.score(busy, targetM: 40000);
      expect(
        b.contributions['busy'],
        closeTo(2 * a.contributions['busy']!, 1e-12),
      );
      expect(b.total, greaterThan(a.total));
    });

    test('a cycleway is a reward', () {
      const s = RouteScorer(LoopPrefs());
      final road = fakeRoute(
        lengthM: 40000,
        tags: 'highway=residential surface=asphalt',
      );
      final path = fakeRoute(
        lengthM: 40000,
        tags: 'highway=cycleway surface=asphalt',
      );
      expect(
        s.score(path, targetM: 40000).contributions['cycleway'],
        closeTo(-1, 1e-9),
      );
      expect(
        s.score(path, targetM: 40000).total,
        lessThan(s.score(road, targetM: 40000).total),
      );
    });
  });

  group('length', () {
    test('the error is relative and symmetric', () {
      const s = RouteScorer(LoopPrefs());
      final shortRoute = fakeRoute(
        lengthM: 36000,
        tags: 'highway=residential surface=asphalt',
      );
      final longRoute = fakeRoute(
        lengthM: 44000,
        tags: 'highway=residential surface=asphalt',
      );
      expect(
        s.features(shortRoute, targetM: 40000).lengthError,
        closeTo(0.1, 1e-12),
      );
      expect(
        s.features(longRoute, targetM: 40000).lengthError,
        closeTo(0.1, 1e-12),
      );
    });

    test('hitting the target beats missing it', () {
      const s = RouteScorer(LoopPrefs());
      final onTarget = fakeRoute(
        lengthM: 40000,
        tags: 'highway=residential surface=asphalt',
      );
      final tooLong = fakeRoute(
        lengthM: 70000,
        tags: 'highway=residential surface=asphalt',
      );
      expect(
        s.score(onTarget, targetM: 40000).total,
        lessThan(s.score(tooLong, targetM: 40000).total),
      );
    });
  });

  test('a short, paved, quiet loop beats a long, gravelly, busy one', () {
    const scorer = RouteScorer(LoopPrefs());
    final good = scorer.score(
      fakeRoute(
        lengthM: 41000,
        tags: 'highway=cycleway surface=asphalt',
        ascentPerKm: 8,
      ),
      targetM: 40000,
    );
    final bad = scorer.score(
      fakeRoute(
        lengthM: 78000,
        tags: 'highway=primary surface=gravel',
        ascentPerKm: 30,
        shape: FakeShape.outAndBack,
      ),
      targetM: 40000,
    );
    expect(good.total, lessThan(bad.total));
  });

  test('the feature vector is exposed for the UI', () {
    const scorer = RouteScorer(LoopPrefs());
    final score = scorer.score(
      fakeRoute(lengthM: 44000, tags: 'highway=track surface=gravel'),
      targetM: 40000,
    );
    final map = score.features.toMap();
    expect(
      map.keys,
      containsAll(<String>[
        'lengthM',
        'targetM',
        'lengthError',
        'ascentPerKm',
        'unpavedShare',
        'cyclewayShare',
        'busyShare',
        'repeatedSegmentRatio',
      ]),
    );
    expect(map['lengthM'], 44000);
    expect(map['unpavedShare'], closeTo(1, 1e-9));
    expect(
      score.contributions.keys,
      containsAll(<String>[
        'lengthError',
        'hills',
        'surface',
        'cycleway',
        'busy',
        'repeated',
      ]),
    );
    var sum = 0.0;
    for (final v in score.contributions.values) {
      sum += v;
    }
    expect(score.total, closeTo(sum, 1e-12));
    expect(score.toString(), contains('LoopScore'));
    expect(score.features.toString(), contains('lengthError'));
  });

  test('a zero target does not divide by zero', () {
    const scorer = RouteScorer(LoopPrefs());
    final f = scorer.features(
      fakeRoute(lengthM: 1000, tags: 'highway=residential surface=asphalt'),
      targetM: 0,
    );
    expect(f.lengthError, 0);
    expect(f.ascentPerKm, closeTo(10, 1e-9));
  });

  test('the least doubled loop wins, even a few kilometres off the target', () {
    // What the rider sees on the map is the spur, not the odometer: a ring
    // that is 15 % too long beats a bang-on one that doubles a tenth of
    // itself out to the next village and back.
    const scorer = RouteScorer(LoopPrefs());
    final spur = scorer.scoreFeatures(
      const LoopFeatures(
        lengthM: 30000,
        targetM: 30000,
        lengthError: 0,
        ascentPerKm: 12,
        unpavedShare: 0,
        cyclewayShare: 0,
        busyShare: 0,
        repeatedSegmentRatio: 0.098,
      ),
    );
    final ring = scorer.scoreFeatures(
      const LoopFeatures(
        lengthM: 34500,
        targetM: 30000,
        lengthError: 0.15,
        ascentPerKm: 12,
        unpavedShare: 0,
        cyclewayShare: 0,
        busyShare: 0,
        repeatedSegmentRatio: 0.01,
      ),
    );
    expect(ring.total, lessThan(spur.total));
    expect(RouteScorer.repeatWeight, greaterThan(RouteScorer.lengthWeight));
  });
}
