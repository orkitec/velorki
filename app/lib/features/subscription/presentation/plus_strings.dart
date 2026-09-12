import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/plus_subscription.dart';

/// The URL of the terms of use shown on the paywall.
///
/// A placeholder page under the project's own domain; the store review needs
/// a reachable link and this is where it will live.
const String velorkiTermsUrl = 'https://velorki.app/terms';

/// The URL of the privacy policy shown on the paywall.
const String velorkiPrivacyUrl = 'https://velorki.app/privacy';

/// Google Play's subscription management page.
const String playSubscriptionsUrl =
    'https://play.google.com/store/account/subscriptions';

/// The App Store's subscription management page.
const String appStoreSubscriptionsUrl =
    'https://apps.apple.com/account/subscriptions';

/// The name of [feature], for the paywall's feature list.
String plusFeatureTitle(AppLocalizations l10n, PlusFeature feature) =>
    switch (feature) {
      PlusFeature.aiAssistant => l10n.plusFeatureAiAssistant,
      PlusFeature.stravaConnection => l10n.plusFeatureStrava,
      PlusFeature.rwgpsConnection => l10n.plusFeatureRwgps,
      PlusFeature.linkSharing => l10n.plusFeatureLinkSharing,
    };

/// What [feature] does, in one sentence.
String plusFeatureBody(AppLocalizations l10n, PlusFeature feature) =>
    switch (feature) {
      PlusFeature.aiAssistant => l10n.plusFeatureAiAssistantBody,
      PlusFeature.stravaConnection => l10n.plusFeatureStravaBody,
      PlusFeature.rwgpsConnection => l10n.plusFeatureRwgpsBody,
      PlusFeature.linkSharing => l10n.plusFeatureLinkSharingBody,
    };

/// How often a package is billed, e.g. "per month".
String plusPeriodLabel(AppLocalizations l10n, PlusPeriod period) =>
    switch (period) {
      PlusPeriod.weekly => l10n.plusPeriodWeek,
      PlusPeriod.monthly => l10n.plusPeriodMonth,
      PlusPeriod.twoMonthly => l10n.plusPeriodTwoMonths,
      PlusPeriod.threeMonthly => l10n.plusPeriodThreeMonths,
      PlusPeriod.sixMonthly => l10n.plusPeriodSixMonths,
      PlusPeriod.annual => l10n.plusPeriodYear,
      PlusPeriod.lifetime || PlusPeriod.other => l10n.plusPeriodLifetime,
    };

/// The trial or introductory note under a package, or `null` when it has
/// neither.
String? plusIntroLabel(AppLocalizations l10n, PlusPackage package) {
  final offer = package.introOffer;
  if (offer == null) return null;
  if (!offer.isFree) return l10n.plusIntroNote(offer.priceString);
  final days = offer.days;
  return days == null ? l10n.plusTrialNoteGeneric : l10n.plusTrialNote(days);
}
