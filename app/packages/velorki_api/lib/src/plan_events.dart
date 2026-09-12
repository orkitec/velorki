import 'dart:convert';

import 'errors.dart';
import 'models.dart';
import 'sse.dart';

/// One event of a `POST /ai/plan` stream.
///
/// Sealed, so a `switch` over a [PlanEvent] is exhaustive:
///
/// ```dart
/// await for (final event in client.planStream(...)) {
///   switch (event) {
///     case RouteRequestEvent(:final request): router.plan(request);
///     case TextEvent(:final delta): buffer.write(delta);
///     case DoneEvent(): break;
///     case ErrorEvent(:final error): show(error.message);
///   }
/// }
/// ```
sealed class PlanEvent {
  /// Creates a plan event.
  const PlanEvent();
}

/// The model proposed a route: the `route_request` event.
///
/// Sent once by the `plan` step, carrying the arguments of the relay's
/// `propose_route` tool call.
final class RouteRequestEvent extends PlanEvent {
  /// Creates a route-request event.
  const RouteRequestEvent(this.request);

  /// The proposed route, ready to be turned into a routing query.
  final RouteRequest request;

  @override
  bool operator ==(Object other) =>
      other is RouteRequestEvent && other.request == request;

  @override
  int get hashCode => request.hashCode;

  @override
  String toString() => 'RouteRequestEvent($request)';
}

/// A chunk of streamed prose: the `text` event.
///
/// Sent repeatedly by the `describe` step. Concatenate the deltas in order to
/// rebuild the full text.
final class TextEvent extends PlanEvent {
  /// Creates a text event.
  const TextEvent(this.delta);

  /// The next piece of text. May be empty, and never ends with a sentinel.
  final String delta;

  @override
  bool operator ==(Object other) => other is TextEvent && other.delta == delta;

  @override
  int get hashCode => delta.hashCode;

  @override
  String toString() => 'TextEvent(${jsonEncode(delta)})';
}

/// The stream finished normally: the `done` event.
///
/// Always the last event of a successful stream.
final class DoneEvent extends PlanEvent {
  /// Creates a done event.
  const DoneEvent({this.usage, this.model});

  /// Token usage for the request, when the relay reported it.
  final PlanUsage? usage;

  /// The model id the relay used, e.g. `anthropic/claude-...`.
  final String? model;

  @override
  bool operator ==(Object other) =>
      other is DoneEvent && other.usage == usage && other.model == model;

  @override
  int get hashCode => Object.hash(usage, model);

  @override
  String toString() => 'DoneEvent(usage: $usage, model: $model)';
}

/// The relay failed after the stream was already open: the `error` event.
///
/// Once the response headers are out the status code is already 200, so the
/// relay reports failures as this event instead. It is emitted into the stream
/// rather than thrown, so text deltas that already arrived stay usable and the
/// caller decides what to do; the stream then ends normally. Callers that want
/// an exception can rethrow: `if (event is ErrorEvent) throw
/// RelayException(event.error, statusCode: 200);`
final class ErrorEvent extends PlanEvent {
  /// Creates an error event.
  const ErrorEvent(this.error);

  /// The uniform error payload the relay sent.
  final RelayError error;

  @override
  bool operator ==(Object other) => other is ErrorEvent && other.error == error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'ErrorEvent($error)';
}

/// Maps one [SseEvent] onto a [PlanEvent].
///
/// Returns `null` for every event name that is not part of the `/ai/plan`
/// contract — including the default `message` name and keep-alive frames.
/// Unknown events are dropped rather than surfaced, so a relay that adds a new
/// event type does not break an older client.
///
/// Throws [RelayFormatException] when a *known* event carries a payload that
/// cannot be parsed; that is a contract violation worth reporting.
PlanEvent? planEventFromSse(SseEvent event) {
  switch (event.name) {
    case 'route_request':
      return RouteRequestEvent(
        RouteRequest.fromJson(
          decodeJsonObject(event.data, what: 'route_request data'),
        ),
      );
    case 'text':
      return TextEvent(_textDelta(event.data));
    case 'done':
      final json = decodeJsonObject(event.data, what: 'done data');
      final usage = json['usage'];
      final model = json['model'];
      return DoneEvent(
        usage: usage is Map<String, Object?> ? PlanUsage.fromJson(usage) : null,
        model: model is String ? model : null,
      );
    case 'error':
      final Object? decoded;
      try {
        decoded = jsonDecode(event.data);
      } on FormatException catch (e) {
        throw RelayFormatException('error data is not valid JSON', cause: e);
      }
      return ErrorEvent(RelayError.fromBody(decoded));
    default:
      return null;
  }
}

/// Extracts the delta of a `text` event.
///
/// Accepts the contract shape `{"delta": "..."}`, a bare JSON string
/// (`"..."`), and — as a last resort — raw text that is not JSON at all, so a
/// relay streaming plain chunks still produces readable output.
String _textDelta(String data) {
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    return data;
  }
  if (decoded is String) return decoded;
  if (decoded is Map<String, Object?>) {
    final delta = decoded['delta'];
    if (delta is String) return delta;
    if (delta == null) return '';
    throw const RelayFormatException('text data delta is not a string');
  }
  throw const RelayFormatException(
    'text data is neither an object nor a string',
  );
}
