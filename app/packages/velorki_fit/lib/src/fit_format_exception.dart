/// Thrown when a byte buffer is not a FIT file, or is a FIT file that cannot
/// be parsed (bad header, CRC mismatch, truncated records).
///
/// Every failure raised by the underlying `fit_sdk` decoder is translated into
/// this exception, so callers never have to catch a third-party type.
class FitFormatException implements Exception {
  /// Creates a format exception with a human readable [message] and the
  /// optional underlying [cause].
  const FitFormatException(this.message, [this.cause]);

  /// What went wrong, in plain English.
  final String message;

  /// The original error, when this exception wraps one.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'FitFormatException: $message'
      : 'FitFormatException: $message ($cause)';
}
