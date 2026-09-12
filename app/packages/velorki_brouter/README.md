# velorki_brouter

BRouter routing for Velorki: the `RoutingBackend` interface the app talks to,
an HTTP backend for a **self-hosted** BRouter server, and the parsers that turn
BRouter's GeoJSON and its `messages` table into typed results and surface
statistics.

Pure Dart, no Flutter dependency. Depends on `velorki_geo` and `http ^1.2.0`.

## Public API

```dart
abstract class RoutingBackend {
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel});
}

class RouteQuery {
  const RouteQuery({
    required List<LatLng> points,
    String profile = 'trekking',
    int alternativeIdx = 0,
    bool roundTrip = false,
    double? roundTripDistanceM,      // BRouter radius, metres (see below)
    double? roundTripDirectionDeg,
    bool allowSameWayBack = true,
    List<NoGo> nogos = const [],
    Duration? timeout,               // enforced client-side
  });
  LatLng get start;
  RouteQuery copyWith({...});
}

class NoGo { const NoGo({required LatLng center, required double radiusM, double? weight}); }

class RouteResult {
  List<TrackPoint> geometry;     // with elevation
  double lengthM, ascentM, descentM, plainAscentM;
  List<SegmentMessage> messages;
  Map<String, dynamic> raw;
  Duration? totalTime;  double? energyJ;  List<double> times;
  String? name, creator;
  SurfaceStats get surfaceStats; // computed on first use
  List<LatLng> get positions;    BoundingBox? get bounds;
  factory RouteResult.fromGeoJson(Map<String, dynamic> json);
}

class SegmentMessage {
  LatLng position; double elevationM, distanceM, timeS, energyJ;
  int costPerKm, elevCost, turnCost, nodeCost, initialCost;
  Map<String, String> wayTags, nodeTags, raw;
  String? get highway, surface;
  static List<SegmentMessage> parseTable(List<dynamic> messages);
  static Map<String, String> parseTags(String? s);
  static const List<String> headerColumns;
}

class SurfaceStats {
  factory SurfaceStats.fromMessages(List<SegmentMessage> messages, double totalLengthM);
  double pavedShare, unpavedShare, unknownShare, cyclewayShare, busyShare;
  double coveredLengthM, totalLengthM;
  static const SurfaceStats empty;
}

class BRouterHttpBackend implements RoutingBackend {
  BRouterHttpBackend(String baseUrl, {http.Client? client,
      Duration defaultTimeout = const Duration(seconds: 25), int? roundTripPoints});
  Uri buildUri(RouteQuery q);                                   // testable
  static RouteResult parseResponse(int statusCode, String body); // testable
  void close();
}

enum RoutingErrorKind { network, noRoute, invalid, cancelled }
class RoutingException implements Exception { RoutingErrorKind kind; String message; Object? cause; int? statusCode; }
class CancelToken { bool get isCancelled; String? get reason; Future<void> get whenCancelled; void cancel([String reason]); }
```

## BRouter parameters, as upstream really spells them

Verified against `abrensch/brouter` master (`RoutingParamCollector.java`,
`RouteServer.java`, `RoutingEngine.java`, `CheapRuler.java`, `FormatJson.java`),
checked 2026-09-12.

| what | parameter | notes |
|---|---|---|
| waypoints | `lonlats=lon,lat\|lon,lat` | longitude first |
| profile | `profile=trekking` | `.brf` name without the suffix |
| alternative | `alternativeidx=0..3` | |
| output | `format=geojson` | |
| round trip | `engineMode=4` | the numeric `BROUTER_ENGINEMODE_ROUNDTRIP`; there is **no** `engineMode=roundtrip` |
| round-trip size | `roundTripDistance=<metres>` | camelCase; **metres, not kilometres**, and it is the *radius* of the generated circle, not the route length. Server default 1500. |
| round-trip heading | `roundTripStartDirection=<deg>` | `direction`/`heading` exist but set the generic start direction |
| generated points | `roundTripPoints=3..20` | default 5 |
| no way back | `allowSamewayback=0\|1` | lower-case `w` and `b` |
| avoid areas | `nogos=lon,lat,radius[,weight]\|...` | radius in metres |
| time limit | — | there is no `timeout` query parameter; the server limit is the JVM property `maxRunningTime`, so `RouteQuery.timeout` is enforced by this client |

**`roundTripDistance` is metres, not km.** The value goes straight into
`CheapRuler.destination(ilon, ilat, distance, angle)`, whose `distance`
argument is metres; the default of 1500 is a 1.5 km radius. Sending kilometres
would be off by a factor of 1000. Because BRouter walks out to the circle,
around roughly half of it and back, a round trip is about `(pi + 2) * radius`
long — that is the conversion `velorki_loops` uses to hit a target distance.

## Errors

BRouter answers a failed route with **HTTP 200 and a plain-text body**
(`no track found at pass=0`, `target island detected ...`), so the status code
alone tells you nothing. `parseResponse` sniffs for a leading `{`, classifies
known failure texts as `noRoute` and everything else as `invalid`, and maps
transport failures, timeouts and 5xx to `network`.

`RoutingErrorKind.cancelled` is additive to the `network | noRoute | invalid`
triple the design called for: the loop planner abandons losing candidates and
has to tell a cancellation apart from a real failure.

## Response properties

`RouteResult.fromGeoJson` reads `track-length`, `filtered ascend`,
`plain-ascend`, `total-time`, `total-energy`, `messages` and `times` from the
first `LineString` feature. BRouter emits **no descent**, so `descentM` is
derived as `ascent - (lastElevation - firstElevation)`, clamped at zero — the
identity that keeps ascent, descent and net gain consistent. `times` are
seconds from the start, one per geometry point, and stay a separate list
rather than being written into `TrackPoint.time`, which is reserved for the
absolute timestamps of a recorded ride.

Message rows carry longitude and latitude as **integer microdegrees**; columns
are looked up by header name, not by index.
