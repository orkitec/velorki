// Rides replayed through the real navigation controller and the real
// on-device router, over real streets, with what the rider must never be
// asked to do written down as assertions.
//
// The Madeira scenarios run on the oracle's committed W20_N30 tile, always.
// The New York ones need W75_N40.rd5 in the directory
// VELORKI_NYC_SEGMENTS_DIR names (the nightly routing-scenarios workflow
// downloads it from the tile mirror); without it they are skipped.
//
// Every scenario is ridden in every re-routing mode, and held to what that
// mode promises (see _expectMode).
//
// Every place is a public one; no scenario is anybody's own ride.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart'
    show replanMovedM;
import 'package:velorki/features/navigation/application/off_route_machine.dart'
    show detourAfter, detourRecomputeMovedM;
import 'package:velorki/features/navigation/application/route_check.dart';
import 'package:velorki/features/navigation/application/route_geometry.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/domain/off_route_guidance.dart';
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
    required this.longPlan,
    required this.longPlanName,
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

  /// The two ends of a plan long enough to leave for kilometres and come
  /// back to.
  final (LatLng, LatLng) longPlan;
  final String longPlanName;

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
    longPlan: (LatLng(32.6385, -16.9440), LatLng(32.6477, -16.9086)),
    longPlanName: 'Funchal, Praia Formosa to the Sé cathedral',
    blockM: 200,
    blockAsideM: 60,
  ),
  _Region(
    name: 'New York',
    tile: 'W75_N40',
    segmentsDir: Platform.environment['VELORKI_NYC_SEGMENTS_DIR'],
    plan: const (LatLng(40.7506, -73.9935), LatLng(40.7424, -73.9881)),
    planName: 'Penn Station to Madison Square Park',
    longPlan: const (LatLng(40.7506, -73.9935), LatLng(40.7308, -73.9973)),
    longPlanName: 'Penn Station to Washington Square Park',
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

/// Whether [route] passes the same checks the controller makes.
bool _clean(RouteResult route) =>
    againstOnewayM(route) < 1 && sidewalkM(route, endsM: _endsM) < 1;

/// How far a way back may carry the rider along the street they stand on,
/// or along the plan where it joins it, before it is held to account: a
/// rider stopped on a pavement is taken from where they are.
const double _endsM = 60;

/// What every way back the controller adopted must be.
///
/// New routes are not held to this: they are planned from wherever the
/// rider stands exactly as the planner plans, and the plan itself is only
/// checked where it is made (the plan tests above).
///
/// Where every candidate the router gave was flawed, the controller takes
/// the least bad rather than none; that is allowed, a clean one passed over
/// is not.
void _expectClean(ReplayLog log) {
  for (final adopted in log.adopted.where((a) => !a.replacesPlan)) {
    final result = adopted.result;
    expect(result, isNotNull, reason: 'the adopted route was routed');
    final asked = log.routings.where((r) => r.at == adopted.at);
    if (asked.every((r) => r.result == null || !_clean(r.result!))) continue;
    expect(
      againstOnewayM(result!),
      lessThan(1),
      reason: 'no one-way ridden the wrong way: $log\n${_flaws(result)}',
    );
    expect(
      sidewalkM(result, endsM: _endsM),
      lessThan(1),
      reason: 'no pavement between the ends: $log\n${_flaws(result)}',
    );
  }
}

/// Every way back meets the plan ahead of the rider, and within [withinM]
/// of a rider beside the plan (one a long way out projects onto it
/// anywhere, and the plan's end may be the nearest way back for them).
void _expectAhead(ReplayLog log, {double withinM = 2000}) {
  for (final adopted in log.adopted.where((a) => !a.replacesPlan)) {
    expect(
      adopted.rejoinAlongM,
      greaterThanOrEqualTo(adopted.riderAlongM - 5),
      reason: 'a way back aimed behind the rider: $log',
    );
    if (adopted.riderOffM > 300) continue;
    expect(
      adopted.rejoinAlongM - adopted.riderAlongM,
      lessThanOrEqualTo(withinM),
      reason: 'a way back aimed too far on: $log',
    );
  }
}

/// The recalculations made while the rider was away from the route, one
/// list per stretch away, each with how far the rider had ridden when it
/// was made.
List<List<(double, List<ReplayRouting>)>> _awayStretches(ReplayLog log) {
  final stretches = <List<(double, List<ReplayRouting>)>>[];
  var lastOn = log.steps.isEmpty ? null : log.steps.first.at;
  DateTime? stretchFrom;
  for (final r in log.recalculations) {
    final at = r.first.at;
    // The last on-route fix before this recalculation.
    for (final step in log.steps) {
      if (step.at.isAfter(at)) break;
      if (step.state == OffRouteState.onRoute) lastOn = step.at;
    }
    if (stretchFrom == null || lastOn != stretchFrom) {
      stretches.add(<(double, List<ReplayRouting>)>[]);
      stretchFrom = lastOn;
    }
    stretches.last.add((log.riddenAt(at), r));
  }
  return stretches;
}

/// What [mode] promises, whatever the ride.
void _expectMode(ReplayLog log, RerouteMode mode) {
  switch (mode) {
    case RerouteMode.guideBack:
      // The plan is never replaced.
      expect(
        log.adopted.where((a) => a.replacesPlan),
        isEmpty,
        reason: 'guide me back re-planned: $log',
      );
      _expectAhead(log);
      _expectClean(log);
      // A rider ignoring the way back is asked again only after riding
      // 300 m, or once past its target (which is itself further on than
      // that, less a little for the corner the rider cut).
      for (final stretch in _awayStretches(log)) {
        for (var i = 1; i < stretch.length; i++) {
          expect(
            stretch[i].$1 - stretch[i - 1].$1,
            greaterThanOrEqualTo(detourRecomputeMovedM - 60),
            reason: 'two ways back too close together: $log',
          );
        }
      }
      // The way back is gone once the rider is on the plan again.
      for (final step in log.steps) {
        if (step.state != OffRouteState.onRoute) continue;
        expect(
          step.detourShown,
          isFalse,
          reason: 'a way back left up at ${step.at}: $log',
        );
      }
    case RerouteMode.newRoute:
      expect(
        log.adopted.where((a) => !a.replacesPlan),
        isEmpty,
        reason: 'a new route handed out a way back: $log',
      );
      // Once per real departure, and never twice within 300 m: it cannot
      // loop, whatever the rider does.
      final replans = log.recalculations;
      expect(replans.length, lessThanOrEqualTo(log.departures), reason: '$log');
      for (var i = 1; i < replans.length; i++) {
        expect(
          haversineMeters(
            log.positionAt(replans[i - 1].first.at),
            log.positionAt(replans[i].first.at),
          ),
          greaterThanOrEqualTo(replanMovedM),
          reason: 'two re-plans too close together: $log',
        );
      }
      for (final r in replans) {
        expect(
          r.single.query.points.length,
          greaterThanOrEqualTo(2),
          reason: 'a re-plan goes somewhere',
        );
      }
    case RerouteMode.off:
      expect(log.routings, isEmpty, reason: 'don\'t re-route routed: $log');
      expect(log.adopted, isEmpty);
      // The banner, the watch and the Live Activity still say so.
      for (final step in log.steps) {
        if (step.state == OffRouteState.onRoute) continue;
        expect(step.state, OffRouteState.guiding);
        expect(step.offRoute, isTrue, reason: 'at ${step.at}');
        expect(step.guidanceM, isNotNull, reason: 'at ${step.at}');
      }
  }
}

/// The furthest the banner said the route was.
double _furthestShown(ReplayLog log) => log.steps.fold<double>(
  0,
  (most, s) => s.guidanceM == null || s.guidanceM! < most ? most : s.guidanceM!,
);

void main() {
  for (final region in _regions) {
    group(region.name, () {
      late LocalRoutingBackend backend;
      late RideMaker maker;
      late List<LatLng> plan;
      late List<LatLng> longPlan;

      setUpAll(() async {
        if (region.skip != null) return;
        backend = LocalRoutingBackend(
          segmentsDir: region.segmentsDir!,
          profilesDir: _profiles,
        );
        maker = RideMaker(backend);
        plan = (await maker.route(<LatLng>[region.plan.$1, region.plan.$2]))
            .positions;
        longPlan = (await maker.route(<LatLng>[
          region.longPlan.$1,
          region.longPlan.$2,
        ])).positions;
      });

      tearDownAll(() async {
        if (region.skip != null) return;
        await backend.dispose();
      });

      test(
        '${region.planName}: the plan rides no one-way the wrong way and '
        'keeps off the pavement',
        () async {
          final route = await maker.route(<LatLng>[
            region.plan.$1,
            region.plan.$2,
          ]);
          expect(againstOnewayM(route), lessThan(1), reason: _flaws(route));
          expect(
            sidewalkM(route, endsM: 60),
            lessThan(1),
            reason: _flaws(route),
          );
        },
        timeout: _slow,
        skip: region.skip,
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
            expect(againstOnewayM(route), lessThan(1), reason: _flaws(route));
            expect(
              sidewalkM(route, endsM: 60),
              lessThan(1),
              reason: _flaws(route),
            );
          },
          timeout: _slow,
          skip: region.skip,
        );
      }

      for (final mode in RerouteMode.values) {
        group(mode.name, () {
          Future<ReplayLog> ride(
            List<ReplayFix> fixes, {
            List<LatLng>? on,
            List<LatLng>? stops,
          }) async {
            final line = on ?? plan;
            final log = await replayRide(
              line: line,
              waypoints: stops ?? <LatLng>[line.first, line.last],
              fixes: fixes,
              backend: backend,
              mode: mode,
            );
            _expectMode(log, mode);
            return log;
          }

          test(
            'street-canyon noise alone never takes the ride off the route '
            'and never asks the router',
            () async {
              final log = await ride(
                maker.ride(
                  plan,
                  noise: (i, random) {
                    // A third of the fixes 20-60 m out, reported honestly:
                    // the accuracy covers at least half of the error.
                    if (random.nextDouble() > 0.35) {
                      return (
                        random.nextDouble() * 8,
                        5 + random.nextDouble() * 5,
                      );
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
            'a burst of ten wild fixes reported honestly is not a detour, '
            'and reported badly it still asks the router nothing',
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
            'a one-block detour needs no routing: the rider is back on the '
            'route before a way back would be worked out',
            () async {
              final path = await maker.anyDetour(
                plan,
                region.blockM,
                region.blockAsideM,
                maxFactor: 2,
              );
              final log = await ride(maker.ride(path));
              expect(log.routings, isEmpty, reason: '$log');
              expect(log.longestOff, lessThan(detourAfter), reason: '$log');
            },
            timeout: _slow,
            skip: region.skip,
          );

          test(
            'a two-block detour is handled once at most, ahead within '
            '800 m, and ends back on the route',
            () async {
              final path = await maker.anyDetour(
                plan,
                region.blockM * 5 / 3,
                region.blockAsideM * 2,
              );
              final log = await ride(maker.ride(path));
              expect(log.reroutes, lessThanOrEqualTo(1), reason: '$log');
              _expectAhead(log, withinM: 800);
              expect(log.steps.last.state, OffRouteState.onRoute);
            },
            timeout: _slow,
            skip: region.skip,
          );

          final alongside = region.alongside;
          test(
            '${region.alongsideName ?? 'riding beside the plan'}: a rider on '
            'the next street over the whole way is led forward, never '
            'nagged, and does not flap',
            () async {
              final long = (await maker.route(<LatLng>[
                alongside!.$1,
                alongside.$2,
              ])).positions;
              final path = await maker.beside(long, region.alongsideM);
              final log = await ride(maker.ride(path), on: long);
              // A new route puts the rider back on the route, and riding on
              // their own way takes them off it again: two flips per new
              // route, and new routes at least 300 m apart.
              expect(
                log.flipsPerMinuteMax,
                lessThanOrEqualTo(mode == RerouteMode.newRoute ? 3 : 2),
                reason: '$log',
              );
            },
            timeout: _slow,
            skip:
                region.skip ?? (alongside == null ? 'no parallel plan' : null),
          );

          test(
            '${region.longPlanName}: a detour of three kilometres and more '
            'ends back on the route',
            () async {
              final path = await maker.longDetour(longPlan, 3000);
              final log = await ride(maker.ride(path), on: longPlan);
              expect(log.everOff, isTrue, reason: '$log');
              if (mode == RerouteMode.off) {
                expect(_furthestShown(log), greaterThan(300), reason: '$log');
              } else {
                expect(log.recalculations, isNotEmpty, reason: '$log');
              }
              expect(log.steps.last.state, OffRouteState.onRoute);
            },
            timeout: _slow,
            skip: region.skip,
          );

          test(
            '${region.longPlanName}: a rider who rides the plan backwards '
            'for a while and turns round again is never re-routed',
            () async {
              final total = cumulativeDistances(longPlan).last;
              final path = maker.backAndForth(
                longPlan,
                total * 0.6,
                total * 0.3,
              );
              final log = await ride(maker.ride(path), on: longPlan);
              expect(log.routings, isEmpty, reason: '$log');
              expect(log.everOff, isFalse, reason: '$log');
            },
            timeout: _slow,
            skip: region.skip,
          );

          test(
            '${region.longPlanName}: a rider who skips a stop is never led '
            'back behind them, and a new route keeps the stop',
            () async {
              final (stop, planned) = await maker.stopAside(longPlan, 400);
              final path = longPlan;
              final log = await ride(
                maker.ride(path),
                on: planned,
                stops: <LatLng>[planned.first, stop, planned.last],
              );
              expect(log.everOff, isTrue, reason: '$log');
              if (mode == RerouteMode.newRoute) {
                // The rider never went to it, so every new route still does.
                for (final r in log.recalculations) {
                  expect(r.single.query.points, contains(stop));
                }
              }
            },
            timeout: _slow,
            skip: region.skip,
          );

          test(
            '${region.longPlanName}: a rider who leaves and never comes back '
            'is not nagged',
            () async {
              final path = await maker.awayFor(longPlan, 0.3, 1500);
              final log = await ride(maker.ride(path), on: longPlan);
              expect(log.steps.last.state, isNot(OffRouteState.onRoute));
              expect(
                log.steps.last.offRoute || mode == RerouteMode.newRoute,
                isTrue,
              );
              final away =
                  log.steps.last.riddenM -
                  log.steps
                      .firstWhere((s) => s.state != OffRouteState.onRoute)
                      .riddenM;
              expect(
                log.recalculations.length,
                lessThanOrEqualTo(1 + away / detourRecomputeMovedM),
                reason: '$log',
              );
            },
            timeout: _slow,
            skip: region.skip,
          );

          test(
            '${region.longPlanName}: a rider who comes back after a long way '
            'out is on the plan again, with nothing left drawn beside it',
            () async {
              final path = await maker.outAndBack(longPlan, 0.4, 1200);
              final log = await ride(maker.ride(path), on: longPlan);
              expect(log.everOff, isTrue, reason: '$log');
              expect(log.steps.last.state, OffRouteState.onRoute);
              if (mode == RerouteMode.guideBack) {
                expect(log.steps.last.detourShown, isFalse);
              }
            },
            timeout: _slow,
            skip: region.skip,
          );
        });
      }
    });
  }
}

/// The stretches of [route] against a one-way or on a pavement, for a
/// failure to name.
String _flaws(RouteResult route) {
  final total = route.messages.fold<double>(0, (sum, m) => sum + m.distanceM);
  var along = 0.0;
  final lines = <String>[];
  for (final m in route.messages) {
    along += m.distanceM;
    if (!againstOneway(m.wayTags) && !sidewalk(m.wayTags)) continue;
    lines.add(
      '${m.distanceM.round()} m ending ${along.round()} of ${total.round()} m '
      'at ${m.position.lat.toStringAsFixed(5)},'
      '${m.position.lon.toStringAsFixed(5)}: ${m.wayTags}',
    );
  }
  return lines.join('\n');
}
