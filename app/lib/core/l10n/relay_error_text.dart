import 'package:velorki_api/velorki_api.dart' show RelayError, RelayErrorCode;

import '../../l10n/generated/app_localizations.dart';

/// What the rider reads for a failure of Velorki's relay, by its code.
///
/// The relay's own `message` is English and meant for the log; the code is
/// what the app words.
String relayErrorText(AppLocalizations l10n, RelayError error) =>
    relayCodeText(l10n, error.code);

/// What the rider reads for the relay error [code] (a [RelayErrorCode]).
String relayCodeText(AppLocalizations l10n, String code) => switch (code) {
  RelayErrorCode.notEntitled => l10n.relayPlusNeeded,
  RelayErrorCode.consentRequired => l10n.relayConsentNeeded,
  RelayErrorCode.notFound => l10n.relayNotFound,
  RelayErrorCode.rateLimited => l10n.relayTooManyRequests,
  RelayErrorCode.upstreamError => l10n.relayUpstreamFailed,
  RelayErrorCode.unavailable => l10n.relayBusy,
  _ => l10n.relayRejected,
};
