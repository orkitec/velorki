/// Thrown when input is not a TCX document or cannot be read as one.
class TcxFormatException implements Exception {
  /// Creates the exception with a [message] and the underlying [cause].
  const TcxFormatException(this.message, [this.cause]);

  /// What went wrong, in plain words.
  final String message;

  /// The parser's own error, when there is one.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'TcxFormatException: $message'
      : 'TcxFormatException: $message ($cause)';
}
