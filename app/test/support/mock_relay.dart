/// The relay's `POST /ai/plan`, mocked at the HTTP layer inside the test
/// process.
///
/// Everything above the socket is the app's own: [RelayClient] gets
/// [MockRelay.httpClient] and parses what comes back as it would parse the
/// relay — the SSE framing, the idle timeout, the error bodies — and the
/// controllers, sheets and planner above it run unchanged. No server process.
///
/// What it answers with is the relay's documented contract
/// ([documentedPlanStreams], [documentedErrors]); what a test scripts beyond
/// that is framed the same way and, given a [SchemaCheck], held to the yaml's
/// schemas, as is every request the app sends. It records each request so a
/// test can say what the app sent.
///
/// No Flutter, no `dart:io`: imported by the widget tests and by
/// `integration_test/` alike.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:velorki_api/velorki_api.dart';

import 'relay_contract.dart';

export 'relay_contract.dart';

/// Checks [json] against the schema named [schema] under
/// `components/schemas` of `web/openapi.yaml`, answering what is wrong with
/// it; empty when it conforms. See `openapi_schema.dart`.
typedef SchemaCheck = List<String> Function(String schema, Object? json);

/// One `POST /ai/plan` the app sent.
class RecordedPlanRequest {
  RecordedPlanRequest._(this.headers, this.body);

  /// The headers, by lower-case name.
  final Map<String, String> headers;

  /// The JSON body.
  final Map<String, Object?> body;

  /// `plan`, `describe` or `route`.
  String? get step => body['step'] as String?;

  /// The language tag the answer is asked in.
  String? get locale => body['locale'] as String?;

  /// `metric` or `imperial`.
  String? get units => body['units'] as String?;

  /// What the rider typed, or the route's name for `describe`.
  String? get prompt => body['prompt'] as String?;

  /// The rider's situation: a rounded position, at most.
  Map<String, Object?>? get context => body['context'] as Map<String, Object?>?;

  /// The route asked about or described.
  Map<String, Object?>? get routeSummary =>
      body['route_summary'] as Map<String, Object?>?;

  /// The route's digest, built on the phone.
  Map<String, Object?>? get digest =>
      routeSummary?['digest'] as Map<String, Object?>?;

  /// The ids of the digest's places.
  List<String> get placeIds => [
    for (final p in (digest?['places'] as List<Object?>? ?? const []))
      (p! as Map<String, Object?>)['id']! as String,
  ];

  /// Whether the rider's consent went along.
  bool get consented => headers[RelayClient.consentHeader.toLowerCase()] == '1';

  @override
  String toString() => 'POST /ai/plan ${jsonEncode(body)}';
}

/// One frame of a scripted stream.
class SseFrame {
  const SseFrame._(this.wire, {this.event, this.data});

  /// An event, framed as the relay frames it: `event:`, one `data:` line of
  /// compact JSON, a blank line.
  factory SseFrame.event(String name, Object? data) => SseFrame._(
    'event: $name\ndata: ${jsonEncode(data)}\n\n',
    event: name,
    data: data,
  );

  /// The `: open` comment every stream starts with.
  static const SseFrame open = SseFrame._(': open\n\n');

  /// The keep-alive the relay writes every 20 s.
  static const SseFrame ping = SseFrame._(': ping\n\n');

  /// Bytes the relay would never send, for the parser's tolerance.
  factory SseFrame.raw(String wire) => SseFrame._(wire);

  /// `route_request` with the documented `propose_route` example, [patch]ed.
  factory SseFrame.routeRequest([Map<String, Object?> patch = const {}]) =>
      SseFrame.event('route_request', {
        ...documentedEvent('plan', 'route_request')! as Map<String, Object?>,
        ...patch,
      });

  /// `route_advice` with [advice].
  factory SseFrame.routeAdvice(Map<String, Object?> advice) =>
      SseFrame.event('route_advice', advice);

  /// One `text` delta.
  factory SseFrame.text(String delta) =>
      SseFrame.event('text', <String, Object?>{'delta': delta});

  /// The `done` that ends every successful stream, as documented.
  factory SseFrame.done() =>
      SseFrame.event('done', documentedEvent('plan', 'done'));

  /// An `error` event with the uniform error body.
  factory SseFrame.error(String code, String message) =>
      SseFrame.event('error', <String, Object?>{
        'error': <String, Object?>{'code': code, 'message': message},
      });

  /// What goes over the wire.
  final String wire;

  /// The event name, for an event.
  final String? event;

  /// The decoded payload, for an event.
  final Object? data;
}

/// The data of the first [event] in the documented stream [stream].
Object? documentedEvent(String stream, String event) {
  final lines = onTheWire(stream).split('\n');
  for (var i = 0; i < lines.length - 1; i++) {
    if (lines[i] == 'event: $event') {
      return jsonDecode(lines[i + 1].substring('data: '.length));
    }
  }
  return null;
}

/// How the mock answers one request.
sealed class RelayReply {
  const RelayReply();

  /// The documented stream [name], in one piece.
  factory RelayReply.documented(String name) => _RawReply(onTheWire(name));

  /// [frames] after the `: open` comment, [gap] apart, the first after
  /// [gap] too. With [thenStall] the stream stays open after the last one,
  /// writing nothing, as a connection that died without closing does.
  const factory RelayReply.stream(
    List<SseFrame> frames, {
    Duration gap,
    bool thenStall,
  }) = StreamReply;

  /// Opens the stream and goes silent.
  factory RelayReply.stall() =>
      const StreamReply(<SseFrame>[], thenStall: true);

  /// A documented error response, before the stream opens.
  const factory RelayReply.error(DocumentedError error) = ErrorReply;

  /// Whatever [build] makes of the request, as the model answers what it was
  /// sent: an answer that names a place of the digest the app built.
  const factory RelayReply.answering(
    RelayReply Function(RecordedPlanRequest request) build,
  ) = _BuiltReply;

  /// An HTTP error whose body is not the uniform one: a proxy's page.
  const factory RelayReply.proxyError(int status, String body) =
      _ProxyErrorReply;
}

/// See [RelayReply.stream].
class StreamReply extends RelayReply {
  /// Creates the reply.
  const StreamReply(
    this.frames, {
    this.gap = Duration.zero,
    this.thenStall = false,
  });

  /// The frames after `: open`.
  final List<SseFrame> frames;

  /// The pause before each frame.
  final Duration gap;

  /// Whether the stream stays open, silent, after the last frame.
  final bool thenStall;
}

class _RawReply extends RelayReply {
  const _RawReply(this.wire);
  final String wire;
}

/// See [RelayReply.error].
class ErrorReply extends RelayReply {
  /// Creates the reply.
  const ErrorReply(this.error);

  /// What is answered.
  final DocumentedError error;
}

class _BuiltReply extends RelayReply {
  const _BuiltReply(this.build);
  final RelayReply Function(RecordedPlanRequest request) build;
}

class _ProxyErrorReply extends RelayReply {
  const _ProxyErrorReply(this.status, this.body);
  final int status;
  final String body;
}

/// The mocked relay. Queue a reply per request with [reply]; a request with
/// nothing queued gets its step's documented example.
class MockRelay {
  /// Creates the relay; [schemas] holds requests and scripted payloads to
  /// the yaml, where the yaml is at hand (not on a device).
  MockRelay({this.schemas});

  /// The yaml's schemas, when the test can read them.
  final SchemaCheck? schemas;

  /// The relay's base URL.
  static const String baseUrl = 'https://api.velorki.test';

  /// The RevenueCat id the client sends as its bearer.
  static const String appUserId = r'$RCAnonymousID:velorkitest';

  /// Every `POST /ai/plan`, in order.
  final List<RecordedPlanRequest> requests = <RecordedPlanRequest>[];

  /// The streams still open, for a test that wants to see them closed.
  int get openStreams => _open;
  int _open = 0;

  /// How many streams the app gave up on (cancelled) before they ended.
  int get cancelledStreams => _cancelled;
  int _cancelled = 0;

  final Queue<RelayReply> _replies = Queue<RelayReply>();

  /// The last request.
  RecordedPlanRequest get last => requests.last;

  /// Queues [reply] for the next request.
  void reply(RelayReply reply) {
    _check(reply);
    _replies.add(reply);
  }

  void _check(RelayReply reply) {
    if (reply is StreamReply) {
      for (final frame in reply.frames) {
        _checkFrame(frame);
      }
    }
  }

  /// The HTTP client [RelayClient] sends through.
  late final http.Client httpClient = MockClient.streaming(_handle);

  /// A [RelayClient] on [httpClient], as the app's provider builds it.
  RelayClient client({
    Duration planIdleTimeout = const Duration(seconds: 45),
  }) => RelayClient(
    baseUrl,
    client: httpClient,
    clientId: 'test/1.0.0+1',
    appUserId: appUserId,
    planIdleTimeout: planIdleTimeout,
  );

  void _checkFrame(SseFrame frame) {
    final check = schemas;
    final event = frame.event;
    if (check == null || event == null) return;
    final problems = switch (event) {
      'route_request' => check('ProposeRoute', frame.data),
      'route_advice' => check('RouteAdvice', frame.data),
      'error' => check('Error', frame.data),
      'text' => _textProblems(frame.data),
      'done' => _doneProblems(frame.data),
      _ => const <String>[],
    };
    if (problems.isNotEmpty) {
      throw ArgumentError(
        'a scripted $event the relay could never send: ${problems.join('; ')}',
      );
    }
  }

  static List<String> _textProblems(Object? data) =>
      data is Map && data.length == 1 && data['delta'] is String
      ? const <String>[]
      : const <String>['text data is not {"delta": "..."}'];

  static List<String> _doneProblems(Object? data) =>
      data is Map && data['usage'] is Map && data['model'] is String
      ? const <String>[]
      : const <String>['done data has no usage and model'];

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    http.ByteStream bodyStream,
  ) async {
    final text = await bodyStream.bytesToString();
    if (request.method != 'POST' ||
        request.url.toString() != '$baseUrl/ai/plan') {
      return _json(
        404,
        '{"error":{"code":"not_found","message":"No such '
        'route."}}',
      );
    }
    final headers = {
      for (final e in request.headers.entries) e.key.toLowerCase(): e.value,
    };
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return _json(400, invalidRequest.body);
    }
    final recorded = RecordedPlanRequest._(
      headers,
      (decoded as Map).cast<String, Object?>(),
    );
    requests.add(recorded);

    // What the relay checks before it opens a stream, in its order.
    final bearer = headers['authorization'] ?? '';
    if (!bearer.startsWith('Bearer ') || bearer.length <= 7) {
      return _documented(notEntitled);
    }
    if (!recorded.consented) return _documented(consentRequired);
    final problems = [
      ...?schemas?.call('PlanRequest', recorded.body),
      if (!(headers['accept'] ?? '').contains('text/event-stream'))
        'accept is not text/event-stream',
    ];
    if (problems.isNotEmpty) {
      // Loud in the test log as well: the app sent what the relay refuses.
      // ignore: avoid_print
      print('MockRelay: the relay would refuse $recorded: $problems');
      return _json(
        400,
        jsonEncode({
          'error': {'code': 'invalid_request', 'message': problems.join('; ')},
        }),
      );
    }

    var reply = _replies.isEmpty
        ? RelayReply.documented(recorded.step!)
        : _replies.removeFirst();
    if (reply is _BuiltReply) {
      reply = reply.build(recorded);
      _check(reply);
    }
    return switch (reply) {
      _BuiltReply() => throw StateError('an answer that answers with another'),
      ErrorReply(:final error) => _documented(error),
      _ProxyErrorReply(:final status, :final body) => http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        status,
        headers: const {'content-type': 'text/html'},
      ),
      _RawReply(:final wire) => _sse([SseFrame.raw(wire)], Duration.zero),
      StreamReply(:final frames, :final gap, :final thenStall) => _sse(
        [SseFrame.open, ...frames],
        gap,
        stall: thenStall,
      ),
    };
  }

  http.StreamedResponse _documented(DocumentedError error) =>
      _json(error.status, error.body, headers: error.headers);

  http.StreamedResponse _json(
    int status,
    String body, {
    Map<String, String> headers = const {},
  }) => http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8', ...headers},
  );

  /// Writes [frames], the first at once and each later one [gap] after the
  /// one before, then closes, unless it is to [stall].
  http.StreamedResponse _sse(
    List<SseFrame> frames,
    Duration gap, {
    bool stall = false,
  }) {
    final out = StreamController<List<int>>();
    // Ended, by the last frame or by the app hanging up.
    var ended = false;
    Timer? next;
    _open++;
    // A future of this zone, not the null one a bare onCancel leaves the
    // subscription to answer with: that one lives in the root zone, whose
    // microtasks a widget test's fake clock never runs, and the app's
    // `return` out of an `await for` would wait on it forever.
    out.onCancel = () {
      next?.cancel();
      if (!ended) {
        ended = true;
        _open--;
        _cancelled++;
      }
      return Future<void>.value();
    };
    void write(int i) {
      if (ended) return;
      if (i == frames.length) {
        if (stall) return;
        ended = true;
        _open--;
        unawaited(out.close());
        return;
      }
      out.add(utf8.encode(frames[i].wire));
      if (i + 1 < frames.length && gap > Duration.zero) {
        next = Timer(gap, () => write(i + 1));
      } else {
        write(i + 1);
      }
    }

    write(0);
    return http.StreamedResponse(
      out.stream,
      200,
      headers: const {'content-type': 'text/event-stream; charset=utf-8'},
    );
  }
}
