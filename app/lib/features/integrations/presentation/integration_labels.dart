import '../../../l10n/generated/app_localizations.dart';
import '../common/domain/connected_account.dart';

/// The name of [service], as it is written in the UI.
///
/// Both are brand names and are not translated; they live in the ARB so the
/// translators see them and leave them alone.
String serviceLabel(AppLocalizations l10n, IntegrationService service) =>
    switch (service) {
      IntegrationService.strava => l10n.serviceStrava,
      IntegrationService.rwgps => l10n.serviceRwgps,
    };

/// The wording of the connect button of [service].
///
/// Strava's brand guidelines require "Connect with Strava" verbatim.
String connectLabel(AppLocalizations l10n, IntegrationService service) =>
    switch (service) {
      IntegrationService.strava => l10n.connectionsConnectStrava,
      IntegrationService.rwgps => l10n.connectionsConnectRwgps,
    };
