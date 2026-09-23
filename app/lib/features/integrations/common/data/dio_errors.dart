import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:velorki_api/velorki_api.dart' show RelayError, RelayErrorCode;

import '../domain/integration_exception.dart';

/// Waits for [delay]. Injected in tests so polling does not take 30 seconds.
typedef Sleeper = Future<void> Function(Duration delay);

/// The production [Sleeper].
Future<void> realSleep(Duration delay) => Future<void>.delayed(delay);

/// What the rider reads when the relay itself cannot be reached.
const String relayUnreachableMessage =
    "Velorki's server could not be reached. Check the connection and try "
    'again.';

/// What the rider reads when the relay answered that Plus has lapsed.
const String relayPlusNeededMessage =
    'Velorki Plus is needed to use this connection.';

/// Turns whatever dio threw into an [IntegrationException] fit to show.
///
/// Every call goes through the relay, so there are two speakers to tell
/// apart: an answer in the relay's own error shape is the relay refusing or
/// failing to forward, and anything else is the service's answer, passed
/// back by the relay unchanged. No answer at all means the relay is out of
/// reach, not the service. A rejected request that already carries an
/// [IntegrationException] — the token interceptor rejects with the "not
/// connected" case — is passed straight through.
IntegrationException integrationExceptionFromDio(
  DioException e, {
  required String service,
}) {
  final carried = e.error;
  if (carried is IntegrationException) return carried;

  final status = e.response?.statusCode;
  if (status == null) {
    return IntegrationException(
      IntegrationFailure.unreachable,
      relayUnreachableMessage,
      cause: e,
    );
  }
  final relayError = relayErrorOf(e.response?.data);
  if (relayError != null) {
    return _fromRelay(relayError, e, service: service);
  }
  final detail = describeServiceError(e.response?.data);
  return switch (status) {
    401 || 403 => IntegrationException(
      IntegrationFailure.notConnected,
      'The $service connection is no longer valid. Connect again in '
      'Settings → Connections.',
      cause: e,
    ),
    429 => IntegrationException(
      IntegrationFailure.rateLimited,
      '$service is rate limiting Velorki. Try again in a few minutes.',
      retryAfter: _retryAfter(e.response),
      cause: e,
    ),
    _ => IntegrationException(
      IntegrationFailure.serviceError,
      detail == null
          ? '$service answered with an error ($status).'
          : '$service: $detail',
      cause: e,
    ),
  };
}

/// The relay's own failure, by its code.
IntegrationException _fromRelay(
  RelayError error,
  DioException e, {
  required String service,
}) => switch (error.code) {
  RelayErrorCode.notEntitled => IntegrationException(
    IntegrationFailure.relayUnavailable,
    relayPlusNeededMessage,
    cause: e,
  ),
  // The stored token did not open: wrapped under a key the relay no longer
  // has, or written before tokens were wrapped at all.
  RelayErrorCode.invalidRequest => IntegrationException(
    IntegrationFailure.notConnected,
    'The $service connection is no longer valid. Connect again in '
    'Settings → Connections.',
    cause: e,
  ),
  RelayErrorCode.rateLimited => IntegrationException(
    IntegrationFailure.rateLimited,
    error.message,
    retryAfter:
        _retryAfter(e.response) ??
        (error.retryAfterS == null
            ? null
            : Duration(seconds: error.retryAfterS!)),
    cause: e,
  ),
  // The relay is up but could not reach the service.
  RelayErrorCode.upstreamError => IntegrationException(
    IntegrationFailure.unreachable,
    '$service could not be reached. Check the connection and try again.',
    cause: e,
  ),
  RelayErrorCode.unavailable => IntegrationException(
    IntegrationFailure.relayUnavailable,
    "Velorki's server cannot do this right now. Try again later.",
    cause: e,
  ),
  _ => IntegrationException(
    IntegrationFailure.serviceError,
    error.message,
    cause: e,
  ),
};

/// The relay's uniform error, when [body] is one; `null` for anything a
/// service answered.
///
/// Strict on purpose: only `{"error": {"code": "...", ...}}` counts. Strava
/// answers `{"message", "errors"}` and Ride with GPS `{"errors": [...]}`, and
/// an OAuth-style `{"error": "invalid_token"}` from either must stay theirs.
RelayError? relayErrorOf(Object? body) {
  Object? decoded = body;
  if (decoded is List<int>) {
    try {
      decoded = jsonDecode(utf8.decode(decoded));
    } on Object {
      return null;
    }
  }
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return null;
    }
  }
  if (decoded is! Map) return null;
  final inner = decoded['error'];
  if (inner is! Map || inner['code'] is! String) return null;
  return RelayError.fromJson(inner.cast<String, Object?>());
}

/// Reads a human-readable message out of a service's error body.
///
/// Strava answers `{"message": "...", "errors": [{"resource", "field",
/// "code"}]}`; Ride with GPS answers `{"errors": ["..."]}`. Anything else
/// yields `null` so the caller falls back to the status code.
String? describeServiceError(Object? body) {
  Object? decoded = body;
  if (decoded is List<int>) {
    try {
      decoded = jsonDecode(utf8.decode(decoded));
    } on Object {
      return null;
    }
  }
  if (decoded is String) {
    final text = decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      final trimmed = text.trim();
      return trimmed.isEmpty || trimmed.startsWith('<') ? null : trimmed;
    }
  }
  if (decoded is! Map) return null;

  final message = decoded['message'];
  final errors = decoded['errors'];
  final parts = <String>[
    if (message is String && message.isNotEmpty) message,
    if (errors is List)
      for (final entry in errors)
        if (entry is String && entry.isNotEmpty)
          entry
        else if (entry is Map && entry['code'] is String)
          '${entry['field'] ?? entry['resource'] ?? ''} ${entry['code']}'
              .trim(),
  ];
  return parts.isEmpty ? null : parts.join('; ');
}

Duration? _retryAfter(Response<Object?>? response) {
  final header = response?.headers.value('retry-after');
  final seconds = header == null ? null : int.tryParse(header);
  return seconds == null ? null : Duration(seconds: seconds);
}
