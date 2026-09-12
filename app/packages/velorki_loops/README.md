# velorki_loops

Smart loops for Velorki: candidate strategies, a weighted scorer and the
planner that turns "a nice 60 km loop from here, past the lake" into three real
routes.

**Pure algorithm, no model.** The AI assistant only ever produces a
`LoopRequest`; everything below is deterministic Dart.

Pure Dart, no Flutter dependency. Depends on `velorki_geo` and
`velorki_brouter`.

## Public API

```dart
enum Hills { avoid, neutral, seek }
enum Surface { paved, mixed, gravel }
class LoopPrefs { const LoopPrefs({Hills hills, Surface surface, bool avoidTraffic}); }
class LoopRequest {
  const LoopRequest({required LatLng start, required double targetM,
      List<LatLng> via = const [], String profile = 'trekking',
      LoopPrefs prefs = const LoopPrefs()});
}

abstract class CandidateStrategy {
  String get name;
  Stream<RouteQuery> queries(LoopRequest request);
}
class RoundtripStrategy implements CandidateStrategy {
  const RoundtripStrategy({int directions = 8});
  static const double lengthPerRadius;           // pi + 2
  static double radiusForTarget(double targetM);
}
class ViaOutAndBackStrategy implements CandidateStrategy { const ViaOutAndBackStrategy(); }
class PerimeterStrategy implements CandidateStrategy {
  PerimeterStrategy({int pointsPerCircle = 4, int rotations = 3, int seed, Random? random});
  static double radiusForTarget(double targetM);
}

class LoopFeatures { double lengthM, targetM, lengthError, ascentPerKm,
    unpavedShare, cyclewayShare, busyShare, repeatedSegmentRatio;
    Map<String, double> toMap(); }
class LoopScore { double total; LoopFeatures features; Map<String, double> contributions; }
class RouteScorer {
  const RouteScorer(LoopPrefs prefs);
  LoopFeatures features(RouteResult result, {required double targetM});
  LoopScore score(RouteResult result, {required double targetM});
  LoopScore scoreFeatures(LoopFeatures f);
  double hillsTerm(double ascentPerKm);
  double surfaceTerm(double unpavedShare);
  static double repeatedSegmentRatio(List<LatLng> points);
}

class LoopCandidate { RouteQuery query; RouteResult result; LoopScore score; String strategy; }
class LoopPlanner {
  LoopPlanner({required RoutingBackend backend, List<CandidateStrategy>? strategies,
      RouteScorer? scorer, int concurrency = 3,
      Duration timeout = const Duration(seconds: 25),
      int maxCandidates = 12, int topN = 3});
  Future<List<LoopCandidate>> plan(LoopRequest request);   // top three, best first
  Stream<LoopCandidate> planStream(LoopRequest request);   // completion order
}
```

## Strategies

| strategy | queries | how |
|---|---|---|
| `RoundtripStrategy` | 8 | BRouter `engineMode=4` in 8 directions (0, 45, … 315), `allowSamewayback=0` |
| `ViaOutAndBackStrategy` | 1 or 5 | `start -> via… -> start`, plus four detoured variants |
| `PerimeterStrategy` | 3 | four waypoints on a circle of radius `target / 2pi`, three seeded rotations |

**Round-trip radius.** BRouter's `roundTripDistance` is the *radius* of the
circle it places its generated waypoints on, in metres — see the
`velorki_brouter` README. It walks out to that circle, around roughly half of
it and back, so a round trip is about `(pi + 2) * radius` long;
`radiusForTarget` inverts that.

**Via variants.** The synthetic waypoint sits perpendicular (+90 and -90
degrees) to the start-to-turnaround chord, at its midpoint, at distance
`d = max(0, (targetM - 2 * chord) / 2)`, and is inserted either on the way out
or on the way back — two sides times two positions, four variants. When the
target is already shorter than the plain out-and-back (`d <= 0`) only the plain
variant is proposed. With several vias the *last* one is the turnaround.

**Perimeter** ignores the road network entirely, which is why it is the
fallback: it reliably produces *something* where the round-trip engine gives
up. Its rotations come from a seeded `Random`, so the same request always
produces the same candidates.

## Scoring

`total` is a weighted sum and **lower is better**; it can go negative when the
rewards outweigh the penalties.

| term | weight | value |
|---|---|---|
| `lengthError` | 3.0 | `\|L - target\| / target` |
| `hills` | 1.5 | avoid: `max(0, (a - 8) / 20)`; neutral: `max(0, (a - 15) / 20)`; seek: `-1` inside 10–25 m/km, rising penalties outside |
| `surface` | 1.0 | paved: `unpavedShare`; mixed: `max(0, unpavedShare - 0.4)`; gravel: `-unpavedShare` |
| `cycleway` | -1.0 | `cyclewayShare` (a reward) |
| `busy` | 2.0, doubled when `avoidTraffic` | `busyShare` |
| `repeated` | 2.5 | `repeatedSegmentRatio` |

`repeatedSegmentRatio` hashes each consecutive point pair with both ends
rounded to 4 decimals (about 11 m) and without direction, so riding a road back
the other way counts. A pure out-and-back scores 0.5. Pairs whose ends round to
the same coordinate are skipped.

`LoopScore.features` and `LoopScore.contributions` are both public so the UI
can explain a ranking ("12 % too long, 38 % gravel") instead of showing a bare
number.

## Planner

`plan` collects up to `maxCandidates` queries from the strategies in order,
routes them through a simple `concurrency`-wide worker pool, scores what comes
back, and returns the best `topN`. Queries that fail to route are skipped, so a
flaky network or an unroutable direction degrades the result instead of
breaking it. A `timeout` cancels the whole run through a shared `CancelToken`.

`planStream` does the same work but emits each candidate as soon as it is
scored, in **completion order**, for progressive UI; nothing is routed until
someone listens.

`scorer` is optional because the weights depend on the rider's `LoopPrefs`,
which arrive with the request: when it is `null` the planner builds a
`RouteScorer(request.prefs)` per call. Pass one explicitly only to pin the
weights.

## Testing

`test/fake_routing_backend.dart` holds a `FakeRoutingBackend` that invents
circle or out-and-back routes of a configurable length, surface tag set and
ascent, counts in-flight requests (so concurrency can be asserted) and can be
told which queries to fail. It honours the `CancelToken`, so timeout tests
finish in milliseconds.
