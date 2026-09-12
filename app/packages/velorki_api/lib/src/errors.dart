import 'dart:convert';

/// The error codes the Velorki relay may return in a uniform error body.
///
/// The relay guarantees that every failure it produces itself carries one of
/// these codes. A code the client does not know is still surfaced verbatim in
/// [RelayError.code]; nothing in this package switches exhaustively on it.
abstract final class RelayErrorCode {
  /// The request body or query did not validate (HTTP 400).
  static const String invalidRequest = 'invalid_request';

  /// No valid entitlement was presented (HTTP 401).
  static const String notEntitled = 'not_entitled';

  /// The rider has not consented to the AI features (HTTP 403).
  static const String consentRequired = 'consent_required';

  /// The addressed resource does not exist or has expired (HTTP 404).
  static const String notFound = 'not_found';

  /// A rate limit was hit; see [RelayError.retryAfterS] (HTTP 429).
  static const String rateLimited = 'rate_limited';

  /// A provider behind the relay failed (HTTP 502).
  static const String upstreamError = 'upstream_error';

  /// The relay is not configured for, or cannot currently serve, this
  /// endpoint (HTTP 503). Also used for transport failures on the client side.
  static const String unavailable = 'unavailable';
}

/// The payload of the relay's uniform error body.
///
/// Wire shape: `{"error": {"code": "...", "message": "...",
/// "retry_after_s": 12}}` — see [RelayError.fromBody] for the unwrapping.
class RelayError {
  /// Creates an error payload.
  const RelayError({
    required this.code,
    required this.message,
    this.retryAfterS,
  });

  /// Machine-readable code; one of the constants on [RelayErrorCode], though
  /// an unknown string is carried through unchanged.
  final String code;

  /// Human-readable explanation, in English, meant for logs and — for the
  /// client-error codes — for display to the rider.
  final String message;

  /// How many seconds to wait before retrying, when the relay said so.
  ///
  /// Only `rate_limited` and some `unavailable` responses carry this.
  final int? retryAfterS;

  /// Parses the inner `{code, message, retry_after_s}` object.
  ///
  /// Throws [RelayFormatException] when [json] is not shaped like an error.
  factory RelayError.fromJson(Map<String, Object?> json) {
    final code = json['code'];
    final message = json['message'];
    if (code is! String) {
      throw const RelayFormatException('error.code is missing or not a string');
    }
    final retry = json['retry_after_s'];
    return RelayError(
      code: code,
      message: message is String ? message : '',
      retryAfterS: retry is num ? retry.toInt() : null,
    );
  }

  /// Parses a full uniform error body, tolerating a bare inner object.
  ///
  /// Accepts both `{"error": {...}}` (what the relay sends) and a plain
  /// `{"code": ..., "message": ...}` (what the `error` SSE event sometimes
  /// looks like after an intermediary has unwrapped it).
  ///
  /// Throws [RelayFormatException] when neither shape matches.
  factory RelayError.fromBody(Object? decoded) {
    if (decoded is Map<String, Object?>) {
      final inner = decoded['error'];
      if (inner is Map<String, Object?>) return RelayError.fromJson(inner);
      if (inner is String) {
        // Some proxies flatten the body to {"error": "message"}.
        return RelayError(code: RelayErrorCode.upstreamError, message: inner);
      }
      return RelayError.fromJson(decoded);
    }
    throw const RelayFormatException('not a uniform error body');
  }

  /// Serialises the inner object (not wrapped in `{"error": ...}`).
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (retryAfterS != null) 'retry_after_s': retryAfterS,
  };

  /// Serialises the full uniform error body, wrapped in `{"error": ...}`.
  Map<String, Object?> toBody() => <String, Object?>{'error': toJson()};

  @override
  bool operator ==(Object other) =>
      other is RelayError &&
      other.code == code &&
      other.message == message &&
      other.retryAfterS == retryAfterS;

  @override
  int get hashCode => Object.hash(code, message, retryAfterS);

  @override
  String toString() =>
      'RelayError($code: $message'
      '${retryAfterS == null ? '' : ', retry after ${retryAfterS}s'})';
}

/// Thrown for every relay call that did not succeed.
///
/// This is the only exception type the [RelayClient] request methods throw for
/// a failed call, whatever the cause: a uniform error body, an HTML page from
/// a proxy, an empty body, or a transport failure such as a `SocketException`
/// or an `http.ClientException`. Those are all mapped to a synthesised
/// [RelayError] so callers never have to catch platform exceptions.
class RelayException implements Exception {
  /// Creates a relay exception.
  const RelayException(this.error, {this.statusCode});

  /// The error payload — real or synthesised.
  final RelayError error;

  /// The HTTP status code, or `null` when the request never got a response.
  final int? statusCode;

  /// Shorthand for `error.code`.
  String get code => error.code;

  /// Shorthand for `error.message`.
  String get message => error.message;

  /// Shorthand for `error.retryAfterS`.
  int? get retryAfterS => error.retryAfterS;

  @override
  String toString() =>
      'RelayException('
      '${statusCode == null ? 'no response' : 'HTTP $statusCode'}, $error)';
}

/// Thrown when a response was received but could not be understood.
///
/// Used for malformed JSON, a JSON document of the wrong shape, and unknown
/// enum values in [RouteRequest] — cases where pretending to have a value
/// would be less honest than failing.
class RelayFormatException implements Exception {
  /// Creates a format exception.
  const RelayFormatException(this.message, {this.cause});

  /// What was wrong with the document.
  final String message;

  /// The underlying exception, when this wraps one.
  final Object? cause;

  @override
  String toString() =>
      'RelayFormatException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Decodes [source] as a JSON object.
///
/// Throws [RelayFormatException] when the text is not valid JSON or does not
/// decode to an object.
Map<String, Object?> decodeJsonObject(String source, {String what = 'body'}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (e) {
    throw RelayFormatException('$what is not valid JSON', cause: e);
  }
  if (decoded is! Map<String, Object?>) {
    throw RelayFormatException('$what is not a JSON object');
  }
  return decoded;
}
