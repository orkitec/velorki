import '../../../../core/l10n/localized_text.dart';
import '../../../../l10n/generated/app_localizations.dart';

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
/// Carries its explanation as a [LocalizedText], so the screen that shows it
/// words it in the rider's language. Where a service gave its own reason
/// ("Your activity is still being processed"), that reason is part of the
/// text as the service wrote it: it is more useful than anything the app
/// could invent.
class IntegrationException implements LocalizedException {
  /// Creates an exception.
  IntegrationException(this.failure, this.text, {this.retryAfter, this.cause});

  /// The rider closed the browser or denied access.
  const IntegrationException.cancelled([this.text = _cancelled])
    : failure = IntegrationFailure.cancelled,
      retryAfter = null,
      cause = null;

  /// What went wrong.
  final IntegrationFailure failure;

  /// The explanation, fit to show in a snack bar.
  final LocalizedText text;

  /// How long to wait before trying again, when that is known.
  final Duration? retryAfter;

  /// The underlying error, for the log.
  final Object? cause;

  /// The explanation in English, for the log.
  String get message => text(englishLocalizations);

  @override
  String describe(AppLocalizations l10n) => text(l10n);

  @override
  String toString() => 'IntegrationException(${failure.name}): $message';
}

String _cancelled(AppLocalizations l10n) => l10n.integrationAuthCancelled;
