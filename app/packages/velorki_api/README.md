# velorki_api

Client and models for the **Velorki relay** — the thin backend that holds the
OAuth client secrets of Strava and Ride with GPS and the LLM API key, so the
open-source app does not have to.

Pure Dart: no Flutter, no `dart:ui`, no `dart:io`, no code generation. The only
runtime dependency is `package:http`.

## What it does

| Relay endpoint | Method |
| --- | --- |
| `POST /oauth/strava/token` | `exchangeStravaCode` |
| `POST /oauth/strava/refresh` | `refreshStrava` |
| `POST /oauth/rwgps/token` | `exchangeRwgpsCode` |
| `POST /share` | `createShare` |
| `POST /ai/plan` (SSE) | `planStream` |

Every request carries `X-Velorki-Client: <platform>/<version>`; every
entitlement-gated call carries `Authorization: Bearer <revenuecat app user id>`;
`/ai/plan` additionally carries `X-AI-Consent: 1`.

## Public API

```dart
class RelayClient {
  RelayClient(String baseUrl, {http.Client? client, String? clientId,
                               String? appUserId});

  String get clientId;                     // X-Velorki-Client value
  String? get appUserId;                   // RevenueCat id, sent as a bearer
  Uri uriFor(String path);

  Future<StravaTokens> exchangeStravaCode({required String code,
                                           required String redirectUri});
  Future<StravaTokens> refreshStrava({required String refreshToken});
  Future<RwgpsTokens>  exchangeRwgpsCode({required String code,
                                          required String redirectUri});
  Future<ShareLink>    createShare({required String name, required String gpx,
                                    required ShareSummary summary,
                                    ShareKind kind = ShareKind.route});
  Stream<PlanEvent>    planStream({required String step, required String prompt,
                                   String locale = 'en',
                                   PlanUnits units = PlanUnits.metric,
                                   PlanContext? context,
                                   RouteSummary? routeSummary,
                                   String? appUserId});
  void close();
}

// Server-Sent Events, usable without any HTTP.
Stream<SseEvent> parseSse(Stream<List<int>> body);
Stream<SseEvent> parseSseText(Stream<String> body);
class SseDecoder extends StreamTransformerBase<List<int>, SseEvent> {...}
class SseEvent { String name; String data; String? id; int? retry; }

// /ai/plan events.
sealed class PlanEvent {}
final class RouteRequestEvent extends PlanEvent { RouteRequest request; }
final class TextEvent         extends PlanEvent { String delta; }
final class DoneEvent         extends PlanEvent { PlanUsage? usage; String? model; }
final class ErrorEvent        extends PlanEvent { RelayError error; }
PlanEvent? planEventFromSse(SseEvent event);

// Models — hand-written fromJson/toJson, with ==, hashCode and toString.
class RouteRequest  { double distanceKm; bool loop; RouteStart start;
                      List<String> via; SurfacePreference surface;
                      HillPreference hills; TrafficTolerance trafficTolerance;
                      List<StopKind> stops; ProfileHint profileHint;
                      String? notes; double confidence; }
class RouteStart    { bool useCurrent; String? name; }
class PlanStart     { double lat; double lon; }
class PlanContext   { PlanStart? start; String? startLabel; String? today; }
class SurfaceMix    { double? paved; double? gravel; double? unpaved; }
class RouteSummary  { double distanceKm; double ascentM; SurfaceMix surface;
                      List<String>? waypoints; List<String>? highlights; }
class PlanUsage     { int inputTokens; int outputTokens; }
class StravaTokens  { String accessToken; String refreshToken; int expiresAt;
                      String tokenType; int? expiresIn;
                      Map<String, Object?>? athlete; }
class RwgpsTokens   { String accessToken; String? refreshToken; int? expiresAt;
                      String tokenType; }
class ShareSummary  { double distanceKm; double? ascentM; int? durationS; }
class ShareLink     { String id; String url; int? expiresAt; }

enum SurfacePreference { paved, mixed, gravel }
enum HillPreference    { avoid, neutral, seek }
enum TrafficTolerance  { low, medium, high }
enum StopKind          { cafe, bakery, viewpoint, lake, water, none }
enum ProfileHint       { trekking, fastbike, mtb, gravel }
enum ShareKind         { route, ride }
enum PlanUnits         { metric, imperial }

// Errors.
class RelayError          { String code; String message; int? retryAfterS; }
class RelayException      implements Exception { RelayError error; int? statusCode; }
class RelayFormatException implements Exception { String message; Object? cause; }
abstract final class RelayErrorCode { /* invalid_request, not_entitled, ... */ }
```

## Usage

```dart
final client = RelayClient(
  'https://relay.velorki.app',
  clientId: 'android/1.4.0',
  appUserId: revenueCatAppUserId,
);

try {
  final tokens = await client.exchangeStravaCode(
    code: code,
    redirectUri: 'velorki://oauth/strava',
  );

  await for (final event in client.planStream(
    step: 'plan',
    prompt: 'A gravel loop of about 60 km for Sunday morning.',
    locale: 'de-DE',
    context: const PlanContext(start: PlanStart(lat: 47.99, lon: 7.85)),
  )) {
    switch (event) {
      case RouteRequestEvent(:final request): await routeIt(request);
      case TextEvent(:final delta):           buffer.write(delta);
      case DoneEvent(:final usage):           log('tokens: $usage');
      case ErrorEvent(:final error):          showError(error.message);
    }
  }
} on RelayException catch (e) {
  // Uniform error body, HTML from a proxy, empty body and transport failures
  // all arrive here with a usable code and message.
  showError('${e.code}: ${e.message}');
} finally {
  client.close();
}
```

## Behaviour worth knowing

* **Error mapping.** Every non-2xx response throws `RelayException`. When the
  body is the relay's uniform `{"error": {...}}` document it is used as-is;
  otherwise an error is synthesised from the status code (400 →
  `invalid_request`, 401 → `not_entitled`, 403 → `consent_required`, 404 →
  `not_found`, 429 → `rate_limited`, 503 → `unavailable`, other 5xx →
  `upstream_error`), with a bounded excerpt of the body as the message.
  `retry_after_s` falls back to the `Retry-After` header. A transport failure —
  `SocketException`, `http.ClientException`, anything else — becomes an
  `unavailable` `RelayException`, so callers never catch platform exceptions.
* **`RelayFormatException`** is thrown when a response arrived but could not be
  understood: malformed JSON, a document of the wrong shape, or an unknown enum
  value.
* **Unknown enum values are strict.** A `surface`, `hills`,
  `traffic_tolerance`, `stops`, `profile_hint`, `kind` or `units` string this
  client does not know throws `RelayFormatException` rather than falling back
  to a default. Those values steer a routing query, and a silent wrong guess
  produces a route the rider did not ask for.
* **Out-of-range values are preserved, not clamped.** The ranges in the field
  docs are the relay's contract; the client carries values through verbatim so
  a JSON round trip is lossless and a widened server limit does not break an
  older client.
* **Unknown SSE events are dropped.** `planEventFromSse` returns `null` for any
  event name outside the `/ai/plan` contract — including SSE's default
  `message` name — so a relay that adds an event type does not break older
  clients. A malformed payload on a *known* event still throws.
* **`ErrorEvent` is emitted, not thrown.** Once the SSE stream is open the
  status code is already 200, so the relay reports failures as an `error`
  event. `planStream` yields it as `ErrorEvent` and then ends the stream
  normally, which keeps already-received text deltas usable. Failures *before*
  the stream opens still throw `RelayException`.
* **`planStream` is lazy and single-subscription.** The request is sent when
  the stream is listened to; cancelling the subscription aborts it.
* **`close()` closes the injected client too**, so do not share an
  `http.Client` you still need afterwards.

## Dependencies

| | |
| --- | --- |
| Dart SDK | `^3.13.3` |
| `http` | `^1.2.0` |
| `lints` (dev) | `^6.0.0` |
| `test` (dev) | `^1.25.0` |

## Tests

```
dart format . && dart analyze && dart test
```

Tests use `package:http/testing.dart`'s `MockClient` and `MockClient.streaming`
— nothing touches the network. The SSE decoder is tested independently of HTTP
via `parseSse`, with the body fed in deliberately awkward chunks.
