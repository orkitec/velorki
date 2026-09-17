import '../../../l10n/generated/app_localizations.dart';
import '../domain/ai_consent.dart';
import '../domain/assistant_state.dart';

/// Where a rider reports an answer that was wrong or inappropriate.
///
/// The store questionnaires ask for such a channel for anything that shows
/// model output; a mail link is the smallest thing that is actually read.
const String aiReportMailto =
    'mailto:support@velorki.com?subject=Velorki%20AI%20output%20report';

/// What to show the rider for [problem].
String assistantProblemText(AppLocalizations l10n, AssistantProblem problem) =>
    switch (problem.failure) {
      AssistantFailure.notEntitled => l10n.assistantNotEntitled,
      AssistantFailure.consentRequired => l10n.assistantConsentNeeded,
      AssistantFailure.noRelay => l10n.assistantNoRelay,
      AssistantFailure.noGeocoder => l10n.assistantNoGeocoder,
      AssistantFailure.rateLimited =>
        problem.retryAfterS == null
            ? l10n.assistantRateLimitedSoon
            : l10n.assistantRateLimited(problem.retryAfterS!),
      AssistantFailure.relay => l10n.assistantFailed(
        problem.message ?? l10n.assistantRateLimitedSoon,
      ),
      AssistantFailure.lowConfidence =>
        problem.notes == null || problem.notes!.isEmpty
            ? l10n.assistantLowConfidenceNoNotes
            : l10n.assistantLowConfidence(problem.notes!),
      AssistantFailure.placeNotFound => l10n.assistantPlaceNotFound(
        problem.name ?? '',
      ),
      AssistantFailure.startUnknown => l10n.assistantStartUnknown,
      AssistantFailure.destinationUnknown => l10n.assistantLowConfidenceNoNotes,
    };

/// How the settings screen describes [consent].
String aiConsentDescription(AppLocalizations l10n, AiConsent? consent) =>
    switch (consent) {
      null => l10n.settingsAiConsentNotAsked,
      AiConsent.denied => l10n.settingsAiConsentDenied,
      AiConsent.textOnly => l10n.settingsAiConsentTextOnly,
      AiConsent.withLocation => l10n.settingsAiConsentWithLocation,
    };
