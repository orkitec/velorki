import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/integration_exception.dart';

/// Waits for [delay]. Injected in tests so polling does not take 30 seconds.
typedef Sleeper = Future<void> Function(Duration delay);

/// The production [Sleeper].
Future<void> realSleep(Duration delay) => Future<void>.delayed(delay);

/// Turns whatever dio threw into an [IntegrationException] fit to show.
///
/// A rejected request that already carries one — the token interceptor
/// rejects with the "not connected" case — is passed straight through.
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
      '$service could not be reached. Check the connection and try again.',
      cause: e,
    );
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
