import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:velorki_api/velorki_api.dart';

/// A streaming mock that replays [parts] as separate chunks, so the boundaries
/// fall exactly where the test wants them.
MockClient sseClient(
  List<String> parts, {
  int status = 200,
  void Function(http.BaseRequest request, String body)? onRequest,
}) => MockClient.streaming((request, bodyStream) async {
  if (onRequest != null) {
    onRequest(request, await bodyStream.bytesToString());
  }
  final body = Stream<List<int>>.fromIterable(
    parts.map(utf8.encode).toList(growable: false),
  );
  return http.StreamedResponse(
    body,
    status,
    request: request,
    headers: const <String, String>{
      'content-type': 'text/event-stream; charset=utf-8',
    },
  );
});

void main() {
  const base = 'https://relay.velorki.app';

  const routeJson =
      '{"distance_km":62.5,"loop":true,'
      '"start":{"use_current":true},"via":[],"surface":"mixed",'
      '"hills":"seek","traffic_tolerance":"low","stops":["cafe"],'
      '"profile_hint":"gravel","notes":"Bring lights.","confidence":0.8}';

  group('planStream request', () {
    test('sends the documented method, url, headers and body', () async {
      http.BaseRequest? seen;
      String? sentBody;
      final client = RelayClient(
        '$base/',
        client: sseClient(
          <String>['event: done\ndata: {}\n\n'],
          onRequest: (request, body) {
            seen = request;
            sentBody = body;
          },
        ),
        clientId: 'android/1.4.0',
        appUserId: 'rc_user_42',
      );
      addTearDown(client.close);

      await client
          .planStream(
            step: 'plan',
            prompt: 'A gravel loop for Sunday morning.',
            locale: 'de-DE',
            context: const PlanContext(
              start: PlanStart(lat: 47.99, lon: 7.85),
              startLabel: 'Freiburg',
            ),
          )
          .toList();

      expect(seen!.method, 'POST');
      expect(seen!.url.toString(), '$base/ai/plan');
      expect(seen!.headers['Authorization'], 'Bearer rc_user_42');
      expect(seen!.headers['X-AI-Consent'], '1');
      expect(seen!.headers['X-Velorki-Client'], 'android/1.4.0');
      expect(seen!.headers['Accept'], 'text/event-stream');
      expect(seen!.headers['Content-Type'], 'application/json; charset=utf-8');

      expect(jsonDecode(sentBody!), <String, Object?>{
        'step': 'plan',
        'locale': 'de-DE',
        'units': 'metric',
        'prompt': 'A gravel loop for Sunday morning.',
        'context': <String, Object?>{
          'start': <String, Object?>{'lat': 47.99, 'lon': 7.85},
          'start_label': 'Freiburg',
        },
      });
    });

    test(
      'sends route_summary and imperial units for the describe step',
      () async {
        String? sentBody;
        final client = RelayClient(
          base,
          client: sseClient(<String>[
            'event: done\ndata: {}\n\n',
          ], onRequest: (_, body) => sentBody = body),
          appUserId: 'rc',
        );
        addTearDown(client.close);

        await client
            .planStream(
              step: 'describe',
              prompt: 'Describe it.',
              units: PlanUnits.imperial,
              routeSummary: const RouteSummary(
                distanceKm: 62.4,
                ascentM: 980,
                surface: SurfaceMix(paved: 0.7, gravel: 0.3),
                waypoints: <String>['Freiburg'],
              ),
            )
            .toList();

        final body = jsonDecode(sentBody!) as Map<String, Object?>;
        expect(body['units'], 'imperial');
        expect(body.containsKey('context'), isFalse);
        expect(body['route_summary'], <String, Object?>{
          'distance_km': 62.4,
          'ascent_m': 980.0,
          'surface': <String, Object?>{'paved': 0.7, 'gravel': 0.3},
          'waypoints': <String>['Freiburg'],
        });
      },
    );

    test('the per-call app user id overrides the client-wide one', () async {
      http.BaseRequest? seen;
      final client = RelayClient(
        base,
        client: sseClient(<String>[
          'event: done\ndata: {}\n\n',
        ], onRequest: (request, _) => seen = request),
        appUserId: 'client_wide',
      );
      addTearDown(client.close);

      await client
          .planStream(step: 'plan', prompt: 'x', appUserId: 'per_call')
          .toList();
      expect(seen!.headers['Authorization'], 'Bearer per_call');
    });

    test('the request is only sent when the stream is listened to', () async {
      var sent = false;
      final client = RelayClient(
        base,
        client: sseClient(<String>[
          'event: done\ndata: {}\n\n',
        ], onRequest: (_, _) => sent = true),
      );
      addTearDown(client.close);

      final stream = client.planStream(step: 'plan', prompt: 'x');
      expect(sent, isFalse);
      await stream.toList();
      expect(sent, isTrue);
    });
  });

  group('planStream events', () {
    test('maps a realistic plan stream onto typed events', () async {
      final client = RelayClient(
        base,
        client: sseClient(<String>[
          ': open\n\n',
          'event: route_req',
          'uest\r\ndata: $routeJson\r\n\r\n',
          'event: done\ndata: {"usage":{"in":1200,"out":310},',
          '"model":"claude-sonnet"}\n\n',
        ]),
      );
      addTearDown(client.close);

      final events = await client
          .planStream(step: 'plan', prompt: 'A gravel loop.')
          .toList();

      expect(events, hasLength(2));
      final route = (events.first as RouteRequestEvent).request;
      expect(route.distanceKm, 62.5);
      expect(route.surface, SurfacePreference.mixed);
      expect(route.stops, <StopKind>[StopKind.cafe]);
      expect(route.profileHint, ProfileHint.gravel);
      expect(route.notes, 'Bring lights.');

      final done = events.last as DoneEvent;
      expect(done.usage, const PlanUsage(inputTokens: 1200, outputTokens: 310));
      expect(done.model, 'claude-sonnet');
    });

    test(
      'maps describe text deltas, including a bare string payload',
      () async {
        final client = RelayClient(
          base,
          client: sseClient(<String>[
            'event: text\ndata: {"delta":"Eine ruhige "}\n\n'
                'event: text\ndata: "Runde durch den Kaiserstuhl."\n\n'
                'event: text\ndata: {"delta":""}\n\n'
                'event: done\ndata: {"model":"m"}\n\n',
          ]),
        );
        addTearDown(client.close);

        final events = await client
            .planStream(step: 'describe', prompt: 'Describe it.')
            .toList();

        expect(
          events.whereType<TextEvent>().map((e) => e.delta).join(),
          'Eine ruhige Runde durch den Kaiserstuhl.',
        );
        expect(events.last, const DoneEvent(model: 'm'));
      },
    );

    test('drops events that are not part of the contract', () async {
      final client = RelayClient(
        base,
        client: sseClient(<String>[
          'event: progress\ndata: {"pct":10}\n\n'
              'data: an unnamed message event\n\n'
              'event: text\ndata: {"delta":"real"}\n\n'
              'event: done\ndata: {}\n\n',
        ]),
      );
      addTearDown(client.close);

      final events = await client
          .planStream(step: 'describe', prompt: 'x')
          .toList();
      expect(events, <PlanEvent>[const TextEvent('real'), const DoneEvent()]);
    });

    test(
      'an error event mid-stream surfaces as ErrorEvent, not a throw',
      () async {
        // Policy: once the stream is open the status is already 200, so a relay
        // failure is an ErrorEvent and the stream ends normally. Deltas that
        // already arrived stay usable; the caller decides whether to throw.
        final client = RelayClient(
          base,
          client: sseClient(<String>[
            'event: text\ndata: {"delta":"Eine ruhige "}\n\n',
            'event: error\ndata: {"error":{"code":"upstream_error",',
            '"message":"The model request failed."}}\n\n',
          ]),
        );
        addTearDown(client.close);

        final events = await client
            .planStream(step: 'describe', prompt: 'x')
            .toList();

        expect(events, <PlanEvent>[
          const TextEvent('Eine ruhige '),
          const ErrorEvent(
            RelayError(
              code: RelayErrorCode.upstreamError,
              message: 'The model request failed.',
            ),
          ),
        ]);
        expect(events.whereType<DoneEvent>(), isEmpty);
      },
    );

    test('an error event carries retry_after_s', () async {
      final client = RelayClient(
        base,
        client: sseClient(<String>[
          'event: error\ndata: {"error":{"code":"rate_limited",'
              '"message":"Slow down.","retry_after_s":900}}\n\n',
        ]),
      );
      addTearDown(client.close);

      final events = await client
          .planStream(step: 'plan', prompt: 'x')
          .toList();
      final error = (events.single as ErrorEvent).error;
      expect(error.code, RelayErrorCode.rateLimited);
      expect(error.retryAfterS, 900);
    });

    test(
      'a malformed payload on a known event throws RelayFormatException',
      () async {
        final client = RelayClient(
          base,
          client: sseClient(<String>[
            'event: route_request\ndata: not json\n\n',
          ]),
        );
        addTearDown(client.close);

        await expectLater(
          client.planStream(step: 'plan', prompt: 'x').toList(),
          throwsA(isA<RelayFormatException>()),
        );
      },
    );
  });

  group('planStream failures before the stream opens', () {
    test('403 without consent throws RelayException', () async {
      final client = RelayClient(
        base,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(const <String, Object?>{
              'error': <String, Object?>{
                'code': 'consent_required',
                'message': 'AI features require the rider to consent first.',
              },
            }),
            403,
          ),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.planStream(step: 'plan', prompt: 'x').toList(),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', RelayErrorCode.consentRequired)
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('a transport failure throws RelayException', () async {
      final client = RelayClient(
        base,
        client: MockClient((_) async {
          throw http.ClientException('Connection refused');
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.planStream(step: 'plan', prompt: 'x').toList(),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', RelayErrorCode.unavailable)
              .having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
    });
  });

  group('planEventFromSse', () {
    test('accepts raw non-JSON text as a delta', () {
      expect(
        planEventFromSse(const SseEvent(name: 'text', data: 'plain chunk')),
        const TextEvent('plain chunk'),
      );
    });

    test('accepts a bare error object without the error wrapper', () {
      expect(
        planEventFromSse(
          const SseEvent(
            name: 'error',
            data: '{"code":"unavailable","message":"down"}',
          ),
        ),
        const ErrorEvent(
          RelayError(code: RelayErrorCode.unavailable, message: 'down'),
        ),
      );
    });

    test('returns null for an unknown or default event name', () {
      expect(planEventFromSse(const SseEvent(data: '{}')), isNull);
      expect(
        planEventFromSse(const SseEvent(name: 'heartbeat', data: '{}')),
        isNull,
      );
    });

    test('a done event without usage or model still parses', () {
      expect(
        planEventFromSse(const SseEvent(name: 'done', data: '{}')),
        const DoneEvent(),
      );
    });
  });
}
