/// Why a call to Strava or Ride with GPS did not work.
enum IntegrationFailure {
  /// No account is connected, or the stored token was rejected.
  notConnected,

  /// The client-side rate bucket is empty; see [IntegrationException.retryAfter].
  rateLimited,

  /// The service answered, but with an error.
  serviceError,

  /// The service could not be reached at all.
  unreachable,

  /// The upload or task finished, but the service rejected the file.
  rejected,

  /// The rider closed the authorisation page, or denied the scopes.
  cancelled,

  /// The relay is not configured in this build, or refused the request.
  relayUnavailable,
}

/// Everything the integrations throw.
///
/// Carries a message that is already fit to show: the services answer in
/// English and their wording ("Your activity is still being processed") is
/// more useful than anything the app could invent.
class IntegrationException implements Exception {
  /// Creates an exception.
  const IntegrationException(
    this.failure,
    this.message, {
    this.retryAfter,
    this.cause,
  });

  /// The rider closed the browser or denied access.
  const IntegrationException.cancelled([
    this.message = 'The authorisation was cancelled.',
  ]) : failure = IntegrationFailure.cancelled,
       retryAfter = null,
       cause = null;

  /// What went wrong.
  final IntegrationFailure failure;

  /// The explanation, in English, fit to show in a snack bar.
  final String message;

  /// How long to wait before trying again, when that is known.
  final Duration? retryAfter;

  /// The underlying error, for the log.
  final Object? cause;

  @override
  String toString() => 'IntegrationException(${failure.name}): $message';
}
