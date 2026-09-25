// The nightly metric of how often the planner's routes ask a rider to do
// what they should not: forty pairs of places in Midtown and the Upper West
// Side, routed with every bike's profile, and the metres against a one-way
// and along the pavement per hundred kilometres held under a ceiling.
//
// Needs W75_N40.rd5 in VELORKI_NYC_SEGMENTS_DIR, as the New York routing
// scenarios do; the routing-scenarios workflow runs both and puts the
// "ROUTESWEEP" lines in its summary. The upstream profiles are measured
// beside Velorki's own, for the comparison, and held to nothing.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/track_surface.dart' show keepAllTags;
import 'package:velorki/features/navigation/application/route_check.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

final String? _segmentsDir = Platform.environment['VELORKI_NYC_SEGMENTS_DIR'];

String? get _skip {
  final dir = _segmentsDir;
  if (dir == null) return 'VELORKI_NYC_SEGMENTS_DIR is not set';
  if (!File('$dir/W75_N40.rd5').existsSync()) return 'W75_N40.rd5 not in $dir';
  return null;
}

/// The ceilings, per hundred kilometres routed, for Velorki's profiles:
/// against a one-way, and along the pavement between the two ends. About
/// twice what they measured when they were made the default (2026-09-24:
/// 8 and 646 m, 15 and 699, 0 and 1263, 23 and 5373), so the night that
/// fails is the one the data or the app changed.
const Map<RouteProfile, (double, double)> _ceilings = {
  RouteProfile.trekking: (20, 1300),
  RouteProfile.fastbike: (30, 1400),
  RouteProfile.gravel: (15, 2500),
  RouteProfile.mtb: (50, 11000),
};

/// Forty pairs between 14th Street and the Upper West Side, the same ones
/// every night: a seeded walk along the avenues and across them.
List<(LatLng, LatLng)> _pairs() {
  final random = math.Random(7);
  LatLng pick() {
    final along = random.nextDouble() * 6000;
    final across = random.nextDouble() * 2200 - 1100;
    const base = LatLng(40.7380, -73.9990);
    return destinationPoint(destinationPoint(base, 29, along), 119, across);
  }

  return <(LatLng, LatLng)>[for (var i = 0; i < 40; i++) (pick(), pick())];
}

Future<({double km, double againstM, double sidewalkM})> _measure(
  RoutingBackend backend,
  String profile,
) async {
  var km = 0.0;
  var against = 0.0;
  var pavement = 0.0;
  for (final (a, b) in _pairs()) {
    final RouteResult route;
    try {
      route = await backend.route(
        RouteQuery(
          points: <LatLng>[a, b],
          profile: profile,
          profileParams: keepAllTags,
        ),
      );
    } on RoutingException {
      continue;
    }
    km += route.lengthM / 1000;
    against += againstOnewayM(route);
    pavement += sidewalkM(route);
  }
  return (km: km, againstM: against, sidewalkM: pavement);
}

void main() {
  test(
    'the planner\'s routes stay off wrong-way one-ways and pavements',
    () async {
      final backend = LocalRoutingBackend(
        segmentsDir: _segmentsDir!,
        profilesDir: '../brouter/profiles',
      );
      addTearDown(backend.dispose);
      for (final entry in _ceilings.entries) {
        final profile = entry.key;
        final (againstCeiling, pavementCeiling) = entry.value;
        final upstream = await _measure(backend, profile.brouterName);
        final own = await _measure(backend, profile.engineName);
        double per100(double metres, double km) => metres / km * 100;
        void report(
          String name,
          ({double km, double againstM, double sidewalkM}) m,
        ) {
          // ignore: avoid_print
          print(
            'ROUTESWEEP | $name | ${m.km.toStringAsFixed(1)} km '
            '| ${per100(m.againstM, m.km).round()} m against a one-way '
            '| ${per100(m.sidewalkM, m.km).round()} m of pavement, per 100 km',
          );
        }

        report(profile.brouterName, upstream);
        report(profile.engineName, own);
        expect(
          per100(own.againstM, own.km),
          lessThanOrEqualTo(againstCeiling),
          reason: '${profile.engineName}: metres against a one-way',
        );
        expect(
          per100(own.sidewalkM, own.km),
          lessThanOrEqualTo(pavementCeiling),
          reason: '${profile.engineName}: metres of pavement',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
    skip: _skip,
  );
}
