/// Thrown by [GpxCodec.decode] when the input cannot be read as GPX.
///
/// The decoder never lets an exception from its own dependencies escape
/// (`XmlParserException`, `FormatException`, `StateError`, `TypeError`, ...).
/// Whatever went wrong is wrapped here, with the original error kept in
/// [cause] so callers can log it while showing [message] to the user.
class GpxFormatException implements Exception {
  /// Creates a format exception describing [message], optionally caused by
  /// [cause].
  const GpxFormatException(this.message, [this.cause]);

  /// A short, human readable description of what is wrong with the input.
  final String message;

  /// The underlying error, if this exception wraps one.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'GpxFormatException: $message'
      : 'GpxFormatException: $message (caused by $cause)';
}
