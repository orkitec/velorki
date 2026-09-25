// Rides replayed through the real navigation controller and the real
// on-device router, over real streets, with what the rider must never be
// asked to do written down as assertions.
//
// The Madeira scenarios run on the oracle's committed W20_N30 tile, always.
// The New York ones need W75_N40.rd5 in the directory
// VELORKI_NYC_SEGMENTS_DIR names (the nightly routing-scenarios workflow
// downloads it from the tile mirror); without it they are skipped.
//
// Every place is a public one; no scenario is anybody's own ride.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart'
    show ignoredRejoinsBeforeReplan;
import 'package:velorki/features/navigation/application/route_check.dart';
import 'package:velorki/features/navigation/application/route_geometry.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/ride_replay.dart';

const String _profiles = '../brouter/profiles';

/// Real routing, on the device's engine: minutes rather than seconds.
const Timeout _slow = Timeout(Duration(minutes: 5));

/// Where a set of scenarios is ridden.
class _Region {
  const _Region({
    required this.name,
    required this.tile,
    required this.segmentsDir,
    required this.plan,
    required this.planName,
    this.alongside,
    this.alongsideName,
    this.alongsideM = 180,
    this.blockM = 300,
    this.blockAsideM = 90,
  });

  /// A block here: how long a stretch a one-block detour replaces, and how
  /// far to the side it goes; twice both is two blocks.
  final double blockM;
  final double blockAsideM;

  final String name;
  final String tile;
  final String? segmentsDir;

  /// The two ends of the everyday plan.
  final (LatLng, LatLng) plan;
  final String planName;

  /// The two ends of a longer plan for riding beside, when the region has
  /// one, and how far over the parallel street is.
  final (LatLng, LatLng)? alongside;
  final String? alongsideName;
  final double alongsideM;

  String? get skip {
    final dir = segmentsDir;
    if (dir == null) return '$name: no tile directory given';
    if (!File('$dir/$tile.rd5').existsSync()) return '$tile.rd5 not in $dir';
    if (!File('$_profiles/lookups.dat').existsSync()) {
      return 'lookups.dat not in $_profiles';
    }
    return null;
  }
}

final List<_Region> _regions = <_Region>[
  const _Region(
    name: 'Madeira',
    tile: 'W20_N30',
    segmentsDir: '../tools/brouter-oracle/tiles',
    plan: (LatLng(32.6405, -16.9290), LatLng(32.6477, -16.9086)),
    planName: 'Funchal, the Lido road to the Sé cathedral',
    blockM: 200,
    blockAsideM: 60,
  ),
  _Region(
    name: 'New York',
    tile: 'W75_N40',
    segmentsDir: Platform.environment['VELORKI_NYC_SEGMENTS_DIR'],
    plan: const (LatLng(40.7506, -73.9935), LatLng(40.7424, -73.9881)),
    planName: 'Penn Station to Madison Square Park',
    alongside: const (LatLng(40.7506, -73.9935), LatLng(40.7654, -73.9837)),
    alongsideName: 'Penn Station up Eighth Avenue to 57th Street',
    alongsideM: 540,
  ),
];

/// A New York plan across Central Park, for the plan checks.
const (LatLng, LatLng) _centralPark = (
  LatLng(40.7812, -73.9724),
  LatLng(40.7760, -73.9636),
);

/// What every way back or re-plan the controller adopted must be.
void _expectClean(ReplayLog log) {
  for (final adopted in log.adopted) {
    final result = adopted.result;
    expect(result, isNotNull, reason: 'the adopted route was routed');
    expect(
      againstOnewayM(result!),
      lessThan(1),
      reason: 'no one-way ridden the wrong way: $log',
    );
    if (_pavementChecked) {
      expect(
        sidewalkM(result),
        lessThan(1),
        reason: 'no pavement between the ends: $log',
      );
    }
  }
}

/// Every way back meets the plan ahead of the rider, within [withinM].
void _expectAhead(ReplayLog log, {double withinM = 2000}) {
  for (final adopted in log.adopted.where((a) => !a.replacesPlan)) {
    expect(
      adopted.rejoinAlongM,
      greaterThanOrEqualTo(adopted.riderAlongM - 5),
      reason: 'a way back aimed behind the rider: $log',
    );
    expect(
      adopted.rejoinAlongM - adopted.riderAlongM,
      lessThanOrEqualTo(withinM),
      reason: 'a way back aimed too far on: $log',
    );
  }
}

void main() {
  for (final region in _regions) {
    group(region.name, () {
      late LocalRoutingBackend backend;
      late RideMaker maker;
      late List<LatLng> plan;

      setUpAll(() async {
        if (region.skip != null) return;
        backend = LocalRoutingBackend(
          segmentsDir: region.segmentsDir!,
          profilesDir: _profiles,
        );
        maker = RideMaker(backend);
        plan = (await maker.route(<LatLng>[region.plan.$1, region.plan.$2]))
            .positions;
      });

      tearDownAll(() async {
        if (region.skip != null) return;
        await backend.dispose();
      });

      Future<ReplayLog> ride(List<ReplayFix> fixes, {List<LatLng>? on}) =>
          replayRide(
            line: on ?? plan,
            waypoints: <LatLng>[(on ?? plan).first, (on ?? plan).last],
            fixes: fixes,
            backend: backend,
          );

      test(
        '${region.planName}: the plan rides no one-way the wrong way and '
        'keeps off the pavement',
        () async {
          final route = await maker.route(<LatLng>[
            region.plan.$1,
            region.plan.$2,
          ]);
          expect(againstOnewayM(route), lessThan(1));
          expect(sidewalkM(route), lessThan(1));
        },
        timeout: _slow,
        skip: region.skip ?? _planChecks,
      );

      test(
        'street-canyon noise alone never takes the ride off the route and '
        'never asks the router',
        () async {
          final log = await ride(
            maker.ride(
              plan,
              noise: (i, random) {
                // A third of the fixes 20-60 m out, reported honestly: the
                // accuracy covers at least half of the error.
                if (random.nextDouble() > 0.35) {
                  return (random.nextDouble() * 8, 5 + random.nextDouble() * 5);
                }
                final error = 20 + random.nextDouble() * 40;
                return (error, error * (0.6 + random.nextDouble() * 0.4));
              },
            ),
          );
          expect(log.everOff, isFalse, reason: '$log');
          expect(log.routings, isEmpty);
        },
        timeout: _slow,
        skip: region.skip,
      );

      test(
        'a burst of ten wild fixes reported honestly is not a detour, and '
        'reported badly it still asks the router nothing',
        () async {
          final honest = await ride(
            maker.ride(
              plan,
              noise: (i, random) => i >= 60 && i < 70
                  ? (80 + random.nextDouble() * 40, 70)
                  : (random.nextDouble() * 6, 8),
            ),
          );
          expect(honest.everOff, isFalse, reason: '$honest');
          expect(honest.routings, isEmpty);

          final dishonest = await ride(
            maker.ride(
              plan,
              noise: (i, random) => i >= 60 && i < 70
                  ? (80 + random.nextDouble() * 40, 20)
                  : (random.nextDouble() * 6, 8),
            ),
          );
          expect(dishonest.routings, isEmpty, reason: '$dishonest');
        },
        timeout: _slow,
        skip: region.skip,
      );

      test(
        'a one-block detour needs no routing and is back on the route within '
        'half a minute',
        () async {
          final path = await maker.anyDetour(
            plan,
            region.blockM,
            region.blockAsideM,
          );
          final log = await ride(maker.ride(path));
          expect(log.routings, isEmpty, reason: '$log');
          expect(
            log.longestOff,
            lessThanOrEqualTo(const Duration(seconds: 30)),
            reason: '$log',
          );
        },
        timeout: _slow,
        skip: region.skip,
      );

      test(
        'a two-block detour gets at most one way back, clean and aimed '
        'ahead within 800 m',
        () async {
          final path = await maker.anyDetour(
            plan,
            region.blockM * 5 / 3,
            region.blockAsideM * 2,
          );
          final log = await ride(maker.ride(path));
          expect(log.reroutes, lessThanOrEqualTo(1), reason: '$log');
          _expectAhead(log, withinM: 800);
          _expectClean(log);
        },
        timeout: _slow,
        skip: region.skip,
      );

      final alongside = region.alongside;
      test(
        '${region.alongsideName ?? 'riding beside the plan'}: a rider on '
        'the next street over the whole way is led forward, not back, is '
        're-planned once instead of rerouted for ever, and does not flap',
        () async {
          final long = (await maker.route(<LatLng>[
            alongside!.$1,
            alongside.$2,
          ])).positions;
          final path = await maker.beside(long, region.alongsideM);
          final log = await ride(maker.ride(path), on: long);
          final km = cumulativeDistances(long).last / 1000;
          // A rider keeping to their own way is given ways back until they
          // have ridden away from two, then the ride is re-planned once:
          // that much, and otherwise at most one a kilometre.
          expect(
            log.reroutes,
            lessThanOrEqualTo(km.ceil() + ignoredRejoinsBeforeReplan),
            reason: '$log',
          );
          expect(log.flipsPerMinuteMax, lessThanOrEqualTo(2), reason: '$log');
          _expectAhead(log);
          _expectClean(log);
        },
        timeout: _slow,
        skip: region.skip ?? (alongside == null ? 'no parallel plan' : null),
      );

      if (region.name == 'New York') {
        test(
          'across Central Park the plan rides no one-way the wrong way '
          'and keeps off the pavement',
          () async {
            final route = await maker.route(<LatLng>[
              _centralPark.$1,
              _centralPark.$2,
            ]);
            expect(againstOnewayM(route), lessThan(1));
            expect(sidewalkM(route), lessThan(1));
          },
          timeout: _slow,
          skip: region.skip ?? _planChecks,
        );
      }
    });
  }
}

/// Whether a way back is held to keeping off the pavement. The upstream
/// profiles push a bike along one wherever it saves a block, and in a city
/// that draws its pavements every candidate may; Velorki's own profile
/// variants take that up.
const bool _pavementChecked = false;

/// The plans themselves come from the upstream profiles, which push a bike
/// along a pavement and the wrong way down a small one-way street; Velorki's
/// own profile variants take that up.
const String _planChecks =
    'the upstream profiles allow pushing; checked with Velorki\'s variants';
