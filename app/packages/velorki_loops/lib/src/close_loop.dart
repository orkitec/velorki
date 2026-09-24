import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Routes a closed plan in two legs so the way back is not the way there.
///
/// BRouter has no "come home a different way" switch for an ordinary
/// `A -> B -> A` request: `allowSamewayback` only means anything in round-trip
/// mode. So the trick is done here. The outbound leg is routed first, then its
/// geometry is sprinkled with weighted no-go circles and the return leg is
/// routed through them: the roads just ridden are expensive rather than
/// forbidden, so the rider gets another way home wherever the network offers
/// one and still gets home over the only bridge in the valley where it does
/// not.
///
/// The two results are merged into one [RouteResult], which is what the
/// planner shows, saves and exports — as far as everything downstream is
/// concerned it is one route.
class CloseLoopRouter {
  /// Creates a router on top of [backend].
  const CloseLoopRouter(
    this.backend, {
    this.sampleEveryM = closeLoopSampleEveryM,
    this.skipEndsM = closeLoopSkipEndsM,
    this.nogoRadiusM = closeLoopNogoRadiusM,
    this.nogoWeight = closeLoopNogoWeight,
    this.maxNogos = closeLoopMaxNogos,
  });

  /// Where the two legs come from.
  final RoutingBackend backend;

  /// Distance along the outbound geometry between two no-go circles.
  final double sampleEveryM;

  /// How much of either end of the outbound leg stays free of no-gos.
  final double skipEndsM;

  /// Radius of one no-go circle, in metres.
  final double nogoRadiusM;

  /// Cost weight of one no-go circle; see [closeLoopNogoWeight].
  final double nogoWeight;

  /// Upper bound on the number of circles, which go into a URL.
  final int maxNogos;

  /// Routes [closed] — a plan whose last point repeats its first — as an
  /// outbound and a return leg and merges the two.
  ///
  /// [closed] is the query the planner would have sent anyway: its profile,
  /// alternative index and timeout go to the outbound leg. The way home takes
  /// [returnAlternativeIdx] instead, which is what "Another way back" cycles:
  /// the ride out stays put while the ride home is redrawn.
  ///
  /// Falls back to routing [closed] in one go when it is not a closed plan of
  /// at least three points. When the return leg fails, it is retried once
  /// without the no-gos; only if that fails too does the failure reach the
  /// caller, so a loop is never worse off than a plain out-and-back.
  Future<RouteResult> route(
    RouteQuery closed, {
    CancelToken? cancel,
    int returnAlternativeIdx = 0,
  }) async {
    if (!isClosedPlan(closed.points)) {
      return backend.route(closed, cancel: cancel);
    }
    final points = closed.points;
    final outbound = closed.copyWith(
      points: points.sublist(0, points.length - 1),
      nogos: const <NoGo>[],
    );
    final first = await backend.route(outbound, cancel: cancel);

    final second = await routeWayBack(
      backend,
      outbound: first.positions,
      back: closed.copyWith(
        points: <LatLng>[points[points.length - 2], points.last],
        alternativeIdx: returnAlternativeIdx,
      ),
      cancel: cancel,
      sampleEveryM: sampleEveryM,
      skipEndsM: skipEndsM,
      nogoRadiusM: nogoRadiusM,
      nogoWeight: nogoWeight,
      maxNogos: maxNogos,
    );
    return mergeLegs(first, second);
  }

  /// Whether [points] is a plan that starts and ends at the same place, which
  /// is what "close the loop" leaves behind.
  static bool isClosedPlan(List<LatLng> points) =>
      points.length >= 3 && points.first == points.last;
}

/// Routes [back], the way home of a closed plan, so it keeps off the roads
/// of [outbound], the way out that is already drawn.
///
/// The way out is sprinkled with weighted no-go circles (see [nogosAlong])
/// and [back] is routed through them. When that fails, it is retried once
/// without them: coming back the same way beats not coming back at all.
/// Cancellation is never retried.
Future<RouteResult> routeWayBack(
  RoutingBackend backend, {
  required List<LatLng> outbound,
  required RouteQuery back,
  CancelToken? cancel,
  double sampleEveryM = closeLoopSampleEveryM,
  double skipEndsM = closeLoopSkipEndsM,
  double nogoRadiusM = closeLoopNogoRadiusM,
  double nogoWeight = closeLoopNogoWeight,
  int maxNogos = closeLoopMaxNogos,
}) async {
  final nogos = nogosAlong(
    outbound,
    sampleEveryM: sampleEveryM,
    skipEndsM: skipEndsM,
    radiusM: nogoRadiusM,
    weight: nogoWeight,
    maxNogos: maxNogos,
  );
  try {
    return await backend.route(back.copyWith(nogos: nogos), cancel: cancel);
  } on RoutingException catch (e) {
    if (e.kind == RoutingErrorKind.cancelled || nogos.isEmpty) rethrow;
    // The no-gos made the way home unroutable — an island, a single track
    // in and out.
    return backend.route(back, cancel: cancel);
  }
}

/// Distance along the outbound leg between two no-go circles.
const double closeLoopSampleEveryM = 150;

/// How much of either end of the outbound leg stays free of no-gos.
///
/// The return leg has to reconnect to the start and to the turning point, and
/// on both it has no choice but to use the very road it came in on.
const double closeLoopSkipEndsM = 400;

/// Radius of one no-go circle, in metres.
///
/// Wide enough that consecutive circles overlap the way between them at
/// [closeLoopSampleEveryM] spacing, narrow enough not to swallow the parallel
/// street one block over.
const double closeLoopNogoRadiusM = 80;

/// Cost weight of one no-go circle.
///
/// BRouter adds `distance within the circle * weight` to the cost of a way
/// (see `RoutingContext.calcDistance`), where a good road already costs about
/// its own length. A weight of 2 therefore makes a road that was just ridden
/// roughly three times as expensive as fresh tarmac: the router happily takes
/// a detour of up to about three times the length to avoid it, but where the
/// only way home is the way out it still goes. `null`, the forbidding kind of
/// no-go, would instead turn "I would rather not" into "no route found".
const double closeLoopNogoWeight = 2;

/// Upper bound on the number of no-go circles.
///
/// They travel in the query string of the HTTP backend's URL, so a 200 km
/// outbound leg must not turn into a 1300-circle request; the sampling is
/// thinned out instead.
const int closeLoopMaxNogos = 150;

/// Weighted no-go circles along [line], for the return leg to avoid.
///
/// Circles are placed every [sampleEveryM] metres, leaving [skipEndsM] metres
/// free at both ends. When that would produce more than [maxNogos] circles the
/// spacing is stretched until it does not: a very long ride gets a coarser
/// hint rather than an unusable request.
List<NoGo> nogosAlong(
  List<LatLng> line, {
  double sampleEveryM = closeLoopSampleEveryM,
  double skipEndsM = closeLoopSkipEndsM,
  double radiusM = closeLoopNogoRadiusM,
  double weight = closeLoopNogoWeight,
  int maxNogos = closeLoopMaxNogos,
}) {
  if (line.length < 2 || maxNogos <= 0) return const <NoGo>[];
  final total = polylineLengthMeters(line);
  final usable = total - 2 * skipEndsM;
  if (usable <= 0) return const <NoGo>[];

  if (sampleEveryM <= 0) return const <NoGo>[];
  // The samples are counted first and placed by index, sample k at
  // k * step, so how many there are cannot hang on how the sums of
  // distances happen to round: a last sample that lands a hair past the
  // usable end is clamped onto it rather than dropped.
  final fit = (usable / sampleEveryM + 1e-9).floor() + 1;
  final count = fit > maxNogos ? maxNogos : fit;
  final step = fit > maxNogos
      ? (maxNogos > 1 ? usable / (maxNogos - 1) : 0.0)
      : sampleEveryM;

  final out = <NoGo>[];
  var travelled = 0.0;
  var i = 1;
  for (var k = 0; k < count; k++) {
    final at = skipEndsM + (k * step > usable ? usable : k * step);
    // Walk on to the segment the sample falls on; the last segment takes
    // whatever rounding leaves past the end.
    while (i < line.length - 1) {
      final segment = haversineMeters(line[i - 1], line[i]);
      if (travelled + segment >= at) break;
      travelled += segment;
      i++;
    }
    final segment = haversineMeters(line[i - 1], line[i]);
    final fraction = segment <= 0
        ? 0.0
        : ((at - travelled) / segment).clamp(0.0, 1.0);
    out.add(
      NoGo(
        center: _lerp(line[i - 1], line[i], fraction),
        radiusM: radiusM,
        weight: weight,
      ),
    );
  }
  return out;
}

/// One route out of the outbound leg [a] and the return leg [b].
///
/// The join point is in both geometries, so [b]'s first point is dropped;
/// everything that is a sum is summed, everything that is a list is
/// concatenated, and [RouteResult.times] are shifted by the outbound leg's
/// last timestamp so they stay monotonic. The return leg's turn instructions
/// move with its points, and the outbound leg's "you have arrived" hint goes:
/// the ride does not end at the join point any more.
RouteResult mergeLegs(RouteResult a, RouteResult b) {
  final geometry = <TrackPoint>[...a.geometry, ...b.geometry.skip(1)];
  final offset = a.times.isEmpty ? 0.0 : a.times.last;
  final times = (a.times.isEmpty || b.times.isEmpty)
      ? const <double>[]
      : <double>[...a.times, ...b.times.skip(1).map((t) => t + offset)];
  // The dropped first point of [b] is [a]'s last one, so point i of [b]
  // becomes point `a.geometry.length - 1 + i` of the merged geometry.
  final pointOffset = a.geometry.isEmpty ? 0 : a.geometry.length - 1;
  final turns = <TurnHint>[
    ...a.turns.where((t) => t.kind != TurnKind.end),
    ...b.turns.map((t) => t.shifted(pointOffset)),
  ];
  return RouteResult(
    geometry: geometry,
    lengthM: a.lengthM + b.lengthM,
    ascentM: a.ascentM + b.ascentM,
    descentM: a.descentM + b.descentM,
    plainAscentM: a.plainAscentM + b.plainAscentM,
    messages: <SegmentMessage>[...a.messages, ...b.messages],
    raw: <String, dynamic>{
      ...a.raw,
      'velorki-legs': <dynamic>[a.raw, b.raw],
    },
    totalTime: _addDurations(a.totalTime, b.totalTime),
    energyJ: _addDoubles(a.energyJ, b.energyJ),
    times: times,
    turns: turns,
    name: a.name ?? b.name,
    creator: a.creator ?? b.creator,
  );
}

LatLng _lerp(LatLng a, LatLng b, double t) =>
    LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);

Duration? _addDurations(Duration? a, Duration? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a + b;
}

double? _addDoubles(double? a, double? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a + b;
}
