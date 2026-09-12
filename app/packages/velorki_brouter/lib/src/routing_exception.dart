import 'dart:async';

import 'tiles.dart';

/// Why a routing request failed.
enum RoutingErrorKind {
  /// The request never produced an answer: DNS, TCP, TLS, a timeout, or a
  /// non-200 status from the routing server.
  network,

  /// The server answered, but there is no route: an unreachable target, a
  /// start or end not matched to the road network, a missing segment file.
  noRoute,

  /// The request or the answer was not understood: a rejected parameter, a
  /// body that is neither GeoJSON nor a known error text.
  invalid,

  /// The caller cancelled the request through its [CancelToken].
  ///
  /// Additive to the `network | noRoute | invalid` triple, because a
  /// cancellation is not a failure and the planner must be able to tell it
  /// apart when it abandons losing candidates.
  cancelled,

  /// On-device routing was asked for an area whose rd5 tiles are not
  /// downloaded (or are on the wrong format version) and no routing server is
  /// configured. [RoutingException.missingTiles] names them, so the UI can
  /// offer "download N tiles (X MB)".
  missingTiles,
}

/// A routing request that did not produce a [RouteResult].
class RoutingException implements Exception {
  /// Creates a routing exception.
  const RoutingException({
    required this.kind,
    required this.message,
    this.cause,
    this.statusCode,
    this.missingTiles = const <TileName>[],
  });

  /// The category of the failure.
  final RoutingErrorKind kind;

  /// A human-readable explanation, usually the server's own error text.
  final String message;

  /// The underlying error, when there was one.
  final Object? cause;

  /// The HTTP status code, when the failure came from an HTTP backend.
  final int? statusCode;

  /// The rd5 tiles that would have to be downloaded, for
  /// [RoutingErrorKind.missingTiles]; empty for every other kind.
  final List<TileName> missingTiles;

  @override
  String toString() => 'RoutingException(${kind.name}): $message';
}

/// Cooperative cancellation for a routing request.
///
/// The planner hands one token to every candidate it starts and cancels the
/// losers as soon as it has enough winners.
class CancelToken {
  final _completer = Completer<void>();
  String? _reason;

  /// Whether [cancel] has been called.
  bool get isCancelled => _completer.isCompleted;

  /// Why the request was cancelled, if it was.
  String? get reason => _reason;

  /// Completes as soon as the token is cancelled.
  Future<void> get whenCancelled => _completer.future;

  /// Cancels every request holding this token. Calling it twice is a no-op.
  void cancel([String reason = 'cancelled']) {
    if (_completer.isCompleted) return;
    _reason = reason;
    _completer.complete();
  }

  /// The exception a cancelled request throws.
  RoutingException toException() => RoutingException(
    kind: RoutingErrorKind.cancelled,
    message: _reason ?? 'cancelled',
  );
}
