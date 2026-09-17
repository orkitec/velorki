# velorki_brouter

BRouter routing for Velorki: the `RoutingBackend` interface the app talks to,
an HTTP backend for a **self-hosted** BRouter server, an on-device backend
running the `brouter_dart` port, the `CompositeRoutingBackend` that decides
between the two from the downloaded tiles, and the parsers that turn BRouter's
GeoJSON and its `messages` table into typed results and surface statistics.

Pure Dart, no Flutter dependency. Depends on `velorki_geo`, `brouter_dart` and
`http ^1.2.0`; the on-device backend uses `dart:io` and an isolate, so it does
not run on the web.

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
    bool allowSameWayBack = true,    // round trips only (see below)
    List<NoGo> nogos = const [],
    Map<String, String> profileParams = const {},  // profile:<name>=<value>
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
  double offRoadShare;              // no highway tag: a ferry, or a beeline
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

class LocalRoutingBackend implements RoutingBackend {
  LocalRoutingBackend({required String segmentsDir, required String profilesDir,
      int maxMemMb = 64, RoutingWorker? worker, int? roundTripPoints,
      int yieldInterval = 2000});
  Set<TileName> availableTiles();   // the *.rd5 on disk
  RoutingWorker? get worker;        // null until the first route
  Future<void> dispose();
}

class CompositeRoutingBackend implements RoutingBackend {
  CompositeRoutingBackend({LocalRoutingBackend? local, RoutingBackend? remote,
      required Set<TileName> Function() localTiles, String? requiredFormatVersion,
      Map<TileName, String>? localFormatVersions,
      double expandFraction = 0.2, double minExpandMeters = 10000});
  RoutingDecision decide(RouteQuery q);      // pure: what would happen
  List<TileName> requiredTiles(RouteQuery q);
  RoutingSource? get lastSource;             // local | remote, after a route
}

enum RoutingSource { local, remote }
class RoutingDecision {
  RoutingSource? source;                     // null: nothing can route it
  List<TileName> requiredTiles, missingTiles;
  bool get canRoute, hasLocalCoverage;
  int missingBytes(SegmentsManifest manifest);
  RoutingException? get failure;
}

class TileName implements Comparable<TileName> {
  const TileName(int lon0, int lat0);        // multiples of 5
  factory TileName.of(double lat, double lon);
  factory TileName.fromLatLng(LatLng p);
  factory TileName.parse(String s);          // "E10_N45" or "E10_N45.rd5"
  static TileName? tryParse(String s);
  String get name, fileName;                 // E10_N45, E10_N45.rd5
  BoundingBox get bounds;  bool contains(LatLng p);
}
List<TileName> tilesForBounds(BoundingBox bounds);
List<TileName> tilesForRoute(List<LatLng> points,
    {double expandFraction = 0.2, double minExpandMeters = 10000});

class SegmentEntry { TileName tile; int bytes; DateTime? updatedAt; String? formatVersion, sha256; }
class SegmentsManifest {
  factory SegmentsManifest.parse(Object? json);              // manifest.json
  factory SegmentsManifest.parseDirectoryListing(String html); // brouter.de
  List<SegmentEntry> tiles;  Map<TileName, SegmentEntry> get byTile;
  String? formatVersion, brouterVersion, source;  DateTime? generatedAt;
  int get totalBytes;  int bytesFor(Iterable<TileName> wanted);
  SegmentEntry? operator [](TileName tile);
}

// shared by both backends - the one place the wire format lives
Map<String, String> buildQueryParams(RouteQuery q, {int? roundTripPoints});
String buildQueryString(RouteQuery q, {int? roundTripPoints});
RoutingErrorKind classifyBRouterError(String text);

enum RoutingErrorKind { network, noRoute, invalid, cancelled, missingTiles }
class RoutingException implements Exception {
  RoutingErrorKind kind; String message; Object? cause; int? statusCode;
  List<TileName> missingTiles;
}
class CancelToken { bool get isCancelled; String? get reason; Future<void> get whenCancelled; void cancel([String reason]); }
```

## On-device routing

`LocalRoutingBackend` runs the `brouter_dart` port in a `RoutingWorker`
isolate. It builds its request with the **same** `buildQueryParams` the HTTP
backend builds its URL from, and parses the isolate's GeoJSON with the **same**
`BRouterHttpBackend.parseResponse`, so a `RouteResult` from the device is
indistinguishable from one from the server — geometry, length, ascent,
`messages` and `surfaceStats` included. A test asserts exactly that against a
recorded corpus case of `tools/brouter-oracle`.

```dart
final local = LocalRoutingBackend(
  segmentsDir: '$appSupport/brouter/segments',  // the .rd5 tiles
  profilesDir: '$appSupport/brouter/profiles',  // .brf + lookups.dat
  maxMemMb: 64,                                 // BRouter's memoryclass
);

final backend = CompositeRoutingBackend(
  local: local,
  remote: BRouterHttpBackend(config.brouterUrl),
  localTiles: local.availableTiles,
  requiredFormatVersion: '11.2',
  localFormatVersions: tilesFromDatabase,
);

final decision = backend.decide(query);          // before routing anything
if (!decision.hasLocalCoverage) {
  show('download ${decision.missingTiles.length} tiles, '
       '${decision.missingBytes(manifest) ~/ 1048576} MB');
}
final route = await backend.route(query, cancel: token);
backend.lastSource;                              // local or remote
await local.dispose();                           // kills the isolate
```

The isolate is spawned on the first route and reused; requests are serialised
so that cancelling one never kills another. `CancelToken` cancels the search in
the isolate cooperatively (the engine checks every `yieldInterval` node
expansions) and `RouteQuery.timeout` is enforced the same way, reported as
`network`. Engine failures carry BRouter's own error text and are classified
with the same `classifyBRouterError` the HTTP path uses: `noRoute` for "no
track found" and its relatives, `invalid` for anything else.

## The tile rule

BRouter cuts the planet into 5° × 5° rd5 tiles named after their south-west
corner — `lon0 = floor(lon / 5) * 5`, `lat0 = floor(lat / 5) * 5`, written as
the hemisphere letter plus the absolute value: `E10_N45`, `W5_S10`, and
`E0_N0` at the equator on the prime meridian (zero counts as the positive
hemisphere). A tile covers the half-open box `[lon0, lon0+5) × [lat0, lat0+5)`,
so a waypoint at exactly 10° E needs `E10_*`.

`tilesForRoute` is the plan's rule: **the bounding box of the waypoints,
expanded by `max(10 km, 20 % of its diagonal)`, and every 5° tile that
intersects the result.** The margin is there because BRouter's search leaves
the direct corridor; a round trip additionally expands by 1.5 × its radius,
because the generated waypoints sit on that circle.

`CompositeRoutingBackend` applies it:

| situation | backend |
|---|---|
| every required tile on disk, format version matching | `local` |
| anything missing, a server configured | `remote` |
| anything missing, no server | throws `RoutingErrorKind.missingTiles` listing the tiles |

It **never routes locally on partial coverage**: BRouter reads a missing tile
as empty land and would silently return a detour, or nothing at all. When
`requiredFormatVersion` is set, a tile whose recorded version is different — or
unknown — counts as missing, because a tile the engine would refuse to read is
no better than one that is not there.

## The segments manifest

`SegmentsManifest` reads the tile sizes the download UI needs, from either
source: our own mirror's `manifest.json` (written by `brouter/updater/sync.sh`;
both the object shape with `formatVersion` + `tiles` and a bare array of rows
are accepted) or, as a fallback, the brouter.de directory index, where
`href="E5_N45.rd5"` plus the date and size columns are scraped out of the
`<pre>` block. The manifest's `formatVersion` is copied onto every entry, which
is what the app stores per tile in `routing_tiles`.

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
| round-trip heading | `direction=<deg>` | without it BRouter chooses a random bearing; `roundTripStartDirection` does not exist in 1.7.10 |
| generated points | `roundTripPoints=3..20` | default 5 |
| no way back | `allowSamewayback=0\|1` | lower-case `w` and `b`; only sent as `1` for a round trip, where it means "home the way you came". On a plain route the engine reads `1` as "append the mirrored waypoints" and doubles the route |
| profile variables | `profile:<name>=<value>` | injected as an `assign` in front of the profile, so it overrides what the profile declares (`profile:allow_ferries=0`) and is harmless when the profile has no such variable |
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
has to tell a cancellation apart from a real failure. `missingTiles` is the
second addition, for the on-device path with no server behind it; the exception
then carries the `TileName`s the region download has to fetch.

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

## Tests

`dart test` runs everything; the tests that need real rd5 tiles skip cleanly
unless `BROUTER_SEGMENTS_DIR` points at a directory holding them (locally
`tools/brouter-oracle/.cache/segments4`, filled by
`tools/brouter-oracle/fetch.sh`). `BROUTER_PROFILES_DIR` defaults to the repo's
`brouter/profiles` and `BROUTER_ORACLE_DIR` to `tools/brouter-oracle`.

```sh
dart test                                             # skips the tile-backed tests
BROUTER_SEGMENTS_DIR=../../../tools/brouter-oracle/.cache/segments4 dart test
```
