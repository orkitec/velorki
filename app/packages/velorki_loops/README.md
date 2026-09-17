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
const Map<String, String> loopProfileParams;     // {'allow_ferries': '0'}
class RoundtripStrategy implements CandidateStrategy {
  const RoundtripStrategy({int directions = 8, double offsetDeg = 0,
      bool allowSameWayBack = false});
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

class RepeatedGeometry {
  const RepeatedGeometry({required double repeatedM, required double totalM});
  factory RepeatedGeometry.of(List<LatLng> points, {int precision = 4});
  double get ratio;
}
class LoopQuality {
  factory LoopQuality.of(RouteResult result,
      {int precision = 4, List<LatLng> waypoints = const []});
  double lengthM, offRoadM, waypointOffsetM; RepeatedGeometry repeated;
  double get offRoadShare, repeatedShare;
}
class LoopFilter {
  const LoopFilter({double maxOffRoadM = 100, double maxRepeatedShare = 0.1,
      double maxWaypointOffsetM = 500, double maxLengthError = 0.25});
  static const LoopFilter none;
  String? reject(LoopQuality quality, {bool ridesBackTheSameWay = false});
  String? tooFarFromTarget(LoopQuality quality, {required double targetM});
}
const double loopMaxLengthError;                 // 0.25
List<LatLng> syntheticPoints(LoopRequest request, RouteQuery query);
RouteQuery? retryQuery(LoopRequest request, RouteQuery query, {RouteResult? result});

class LoopCandidate { RouteQuery query; RouteResult result; LoopScore score;
    String strategy; LoopQuality quality; bool farFromTarget; }
class LoopPlanner {
  LoopPlanner({required RoutingBackend backend, List<CandidateStrategy>? strategies,
      RouteScorer? scorer, int concurrency = 3,
      Duration timeout = const Duration(seconds: 25),
      int maxCandidates = 12, int topN = 3,
      LoopFilter filter = const LoopFilter(), int maxRetries = 1});
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

**No ferries.** Every query carries `loopProfileParams`
(`profile:allow_ferries=0`). BRouter invents its round-trip waypoints on a
circle and snaps each of them to the nearest way, and for a coastal town the
nearest way to a point in the sea is the ferry line — drawn in OSM as one
straight segment over open water and ridden out and back. Profiles that declare
`allow_ferries` (trekking, fastbike, mtb) obey it; for the rest `LoopFilter`
throws the answer away.

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
| `repeated` | 8.0 | `repeatedSegmentRatio` |

`repeatedSegmentRatio` hashes each consecutive point pair with both ends
rounded to 4 decimals (about 11 m) and without direction, so riding a road back
the other way counts, and adds up the **metres** of the pairs it has already
seen (`RepeatedGeometry`). A pure out-and-back scores 0.5. Pairs whose ends
round to the same coordinate are skipped. Metres rather than pairs because a
route's points are OSM nodes: a four-kilometre ferry leg is one pair and a
roundabout is thirty, and counting pairs called a route that spent a quarter of
its length doubled back "2 % repeated".

## Filtering

Scoring ranks loops against taste; `LoopFilter` decides whether the thing is a
loop at all, and the planner drops what it rejects:

| rule | default | why |
|---|---|---|
| `maxOffRoadM` | 100 m | metres with no `highway` tag — a ferry, or a beeline drawn straight from a waypoint that had no way near it |
| `maxRepeatedShare` | 0.1 | a tenth is the street the ride leaves and comes home on; a fifth is a two-kilometre spur out and back, which is what a coastal round trip keeps producing and what a rider calls "not a loop". Skipped when the query allows the same way back, which is the rider asking for one |
| `maxWaypointOffsetM` | 500 m | how far an invented point ended up from the route it produced. More than that and it was in the water: the engine snapped it somewhere else and the loop is not the one the strategy proposed. Only `syntheticPoints` are judged — never the rider's `start` or `via` |

**Too far from the target** is a fourth rule and a softer one, `maxLengthError`
(a quarter), asked through `tooFarFromTarget` rather than `reject`: a 38 km
answer to a 30 km request *is* a loop, it is just not the one the rider asked
for. The planner holds it back instead of throwing it away, retries the query
with the radius scaled by `target / length`, and shows the held candidate only
once every retry is spent and nothing nearer the target came back — flagged
`LoopCandidate.farFromTarget`, so the sheet's log says the budget ran out
rather than leaving the rider wondering. A quarter is the band a rider reads
as "about what I asked for"; it is deliberately wider than the scorer's
`lengthError` term, which then ranks what is inside it. From Funchal a 30 km
request used to answer 38 km first, because the candidates nearest the target
were the ones rejected as doubled and only a later rotated search found the
30.7 km ring.

A rejected candidate, and one that did not route at all, is retried through
`retryQuery`: the bearing rotates by 18 degrees so the invented waypoints land
somewhere else, and the round-trip radius is scaled by how far the answer missed
the target (clamped to 0.45–1.5), which is also what pulls an overlong mountain
loop back towards the distance that was asked for. For a query with explicit
waypoints the same rotation and scaling move the synthetic points round and
towards the start, and leave the rider's own `start` and `via` alone.

Everything gets one rotation. Past that only a strategy that has produced
**nothing at all** keeps turning the wheel, up to `maxRetries` (3) — a coastal
start where every invented bearing runs into the sea needs a few goes to find
land, while a strategy that already has a loop to show should not spend the
deadline on more.

The repeat weight is deliberately higher than the length weight: among the
candidates that survive `LoopFilter`, the least doubled one should win even
when it is a few kilometres further from the target, because the spur is what
the rider sees on the map. A tenth ridden twice costs as much as being 27 % off
the distance.

`LoopScore.features` and `LoopScore.contributions` are both public so the UI
can explain a ranking ("12 % too long, 38 % gravel") instead of showing a bare
number.

## Planner

`plan` collects up to `maxCandidates` queries from the strategies in order,
routes them through a simple `concurrency`-wide worker pool, filters and scores
what comes back, and returns the best `topN`. Queries that fail to route are
skipped, so a flaky network or an unroutable direction degrades the result
instead of breaking it; a retry may be appended to the queue while it runs. A `timeout` cancels the whole run through a shared `CancelToken`.

A candidate the filter accepts but `tooFarFromTarget` flags is held back
rather than emitted, and only the held pool is emitted — best first, with
`farFromTarget` set — when the run ends with nothing inside the band. So a run
that routed anything the filter accepts never answers with nothing, whether it
ended on its own or on the deadline.

`planStream` does the same work but emits each candidate as soon as it is
scored, in **completion order**, for progressive UI; nothing is routed until
someone listens.

`scorer` is optional because the weights depend on the rider's `LoopPrefs`,
which arrive with the request: when it is `null` the planner builds a
`RouteScorer(request.prefs)` per call. Pass one explicitly only to pin the
weights.

## Testing

`test/fake_routing_backend.dart` holds a `FakeRoutingBackend` that invents
circle or out-and-back routes of a configurable length, surface tag set,
off-road (ferry) share and ascent — a query with waypoints of its own is drawn
*through them*, the way a router would, so a test can assert on where a
strategy put its synthetic points — counts in-flight requests (so concurrency can be asserted) and can be
told which queries to fail. It honours the `CancelToken`, so timeout tests
finish in milliseconds.
