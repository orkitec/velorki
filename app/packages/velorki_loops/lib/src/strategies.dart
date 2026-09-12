import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'loop_request.dart';

/// Turns a [LoopRequest] into concrete [RouteQuery]s for the planner to try.
///
/// A strategy is a cheap generator: it does no routing itself and never fails,
/// it just proposes. The planner runs the queries, throws away the ones that
/// do not route and scores what is left.
abstract class CandidateStrategy {
  /// Short identifier carried into [LoopCandidate.strategy] for the UI and
  /// for debugging.
  String get name;

  /// The queries this strategy proposes for [request].
  Stream<RouteQuery> queries(LoopRequest request);
}

/// BRouter's own round-trip mode, fired off in eight directions.
///
/// BRouter walks out to a circle of `roundTripDistance` metres, around roughly
/// half of it and back, so a round trip is about `(pi + 2) * radius` long.
/// [radiusForTarget] inverts that to hit [LoopRequest.targetM].
class RoundtripStrategy implements CandidateStrategy {
  /// Creates the round-trip strategy.
  const RoundtripStrategy({this.directions = 8});

  /// How many evenly spaced directions to try (8 gives 0, 45, … 315).
  final int directions;

  /// `(pi + 2)`: a half circle of arc plus two radial legs.
  static const double lengthPerRadius = math.pi + 2;

  /// The BRouter round-trip radius, in metres, that should produce a route of
  /// [targetM] metres.
  static double radiusForTarget(double targetM) => targetM / lengthPerRadius;

  @override
  String get name => 'roundtrip';

  @override
  Stream<RouteQuery> queries(LoopRequest request) async* {
    if (directions <= 0) return;
    final radius = radiusForTarget(request.targetM);
    final step = 360.0 / directions;
    for (var i = 0; i < directions; i++) {
      yield RouteQuery(
        points: [request.start],
        profile: request.profile,
        roundTrip: true,
        roundTripDistanceM: radius,
        roundTripDirectionDeg: i * step,
        allowSameWayBack: false,
      );
    }
  }
}

/// Start to the vias and back, with four detoured variants.
///
/// The plain variant is `start -> via... -> start` with `allowSamewayback=0`,
/// which is already a loop whenever the road network offers a second way home.
/// When the target is longer than twice the start-to-turnaround chord, four
/// more variants push the route out sideways: a synthetic waypoint is placed
/// perpendicular (+90 and -90 degrees) to the chord, at the midpoint, at
/// distance `d = max(0, (targetM - 2 * chord) / 2)`, and inserted either on
/// the way out or on the way back.
class ViaOutAndBackStrategy implements CandidateStrategy {
  /// Creates the via strategy.
  const ViaOutAndBackStrategy();

  @override
  String get name => 'viaOutAndBack';

  @override
  Stream<RouteQuery> queries(LoopRequest request) async* {
    final via = request.via;
    if (via.isEmpty) return;

    final plain = <LatLng>[request.start, ...via, request.start];
    yield RouteQuery(
      points: plain,
      profile: request.profile,
      allowSameWayBack: false,
    );

    final turnaround = via.last;
    final chord = haversineMeters(request.start, turnaround);
    final detour = math.max(0.0, (request.targetM - 2 * chord) / 2);
    if (detour <= 0) return;

    final bearing = bearingDegrees(request.start, turnaround);
    final mid = destinationPoint(request.start, bearing, chord / 2);
    for (final side in const [90.0, -90.0]) {
      final synthetic = destinationPoint(mid, bearing + side, detour);
      // On the way out ...
      yield RouteQuery(
        points: [request.start, synthetic, ...via, request.start],
        profile: request.profile,
        allowSameWayBack: false,
      );
      // ... and on the way back.
      yield RouteQuery(
        points: [request.start, ...via, synthetic, request.start],
        profile: request.profile,
        allowSameWayBack: false,
      );
    }
  }
}

/// A plain geometric fallback: ride round a circle whose circumference is the
/// target distance.
///
/// Four waypoints are placed on a circle of radius `targetM / (2 * pi)` around
/// the start and routed in order; three seeded random rotations give three
/// different loops. It ignores the road network completely, which is exactly
/// why it is the fallback — but it reliably produces *something* where the
/// round-trip engine gives up.
class PerimeterStrategy implements CandidateStrategy {
  /// Creates the perimeter strategy.
  ///
  /// [seed] makes the rotations reproducible, which the tests and the
  /// "same request, same candidates" expectation both rely on.
  PerimeterStrategy({
    this.pointsPerCircle = 4,
    this.rotations = 3,
    int seed = 0x76656c6f,
    math.Random? random,
  }) : _random = random ?? math.Random(seed);

  /// How many waypoints to put on the circle.
  final int pointsPerCircle;

  /// How many rotated variants to emit.
  final int rotations;

  final math.Random _random;

  /// The circle radius, in metres, whose circumference is [targetM].
  static double radiusForTarget(double targetM) => targetM / (2 * math.pi);

  @override
  String get name => 'perimeter';

  @override
  Stream<RouteQuery> queries(LoopRequest request) async* {
    if (pointsPerCircle < 3 || rotations <= 0) return;
    final radius = radiusForTarget(request.targetM);
    final step = 360.0 / pointsPerCircle;
    for (var r = 0; r < rotations; r++) {
      final rotation = _random.nextDouble() * step;
      final ring = <LatLng>[
        for (var i = 0; i < pointsPerCircle; i++)
          destinationPoint(request.start, rotation + i * step, radius),
      ];
      yield RouteQuery(
        points: [request.start, ...ring, request.start],
        profile: request.profile,
        allowSameWayBack: false,
      );
    }
  }
}
