import 'package:flutter/foundation.dart' show TargetPlatform;

import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/plus_subscription.dart';

// The paywall's terms and privacy links; they are the same pages the About
// section and the store listings point at.
export '../../../core/links/velorki_urls.dart'
    show velorkiPrivacyUrl, velorkiTermsUrl;

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

/// What [package] costs and how often, e.g. "€4.99 per month".
String plusPriceLabel(AppLocalizations l10n, PlusPackage package) =>
    l10n.plusPricePeriod(
      package.priceString,
      plusPeriodLabel(l10n, package.period),
    );

/// The trial or introductory note under a package, or `null` when it has
/// neither. It says what is charged once the trial or the introductory
/// price ends, which the App Store wants beside every trial.
String? plusIntroLabel(AppLocalizations l10n, PlusPackage package) {
  final offer = package.introOffer;
  if (offer == null) return null;
  final price = plusPriceLabel(l10n, package);
  if (!offer.isFree) return l10n.plusIntroNote(offer.priceString, price);
  final days = offer.days;
  return days == null
      ? l10n.plusTrialNoteGeneric(price)
      : l10n.plusTrialNote(days, price);
}

/// The auto-renewal terms for the store this build buys through: an iPhone
/// must not mention the other platform's store.
String plusLegalText(AppLocalizations l10n, TargetPlatform platform) =>
    platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
    ? l10n.plusLegalAppStore
    : l10n.plusLegalPlay;
