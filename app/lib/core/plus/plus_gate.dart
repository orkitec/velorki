import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Features that belong to the Velorki Plus subscription: the ones that need
/// our servers. Everything on the phone is free, and so are the Strava and
/// Ride with GPS connections: Strava's API policy forbids charging for
/// anything built on it, and Ride with GPS follows the same rule here.
enum PlusFeature { aiAssistant, linkSharing, weather }

/// The single place that says which features are gated. Moving a feature to
/// the free tier is a one-line change here.
const Set<PlusFeature> gatedFeatures = {
  PlusFeature.aiAssistant,
  PlusFeature.linkSharing,
  PlusFeature.weather,
};

/// Whether the user currently holds the Plus entitlement. The subscription
/// feature overrides this with RevenueCat's customer info; until then it is
/// false, so gated screens show their paywall placeholder. Tests set it
/// through the notifier.
class PlusEntitled extends Notifier<bool> {
  @override
  bool build() => false;

  set value(bool entitled) => state = entitled;
}

final plusEntitledProvider = NotifierProvider<PlusEntitled, bool>(
  PlusEntitled.new,
);

/// True when [feature] may be used right now.
final plusFeatureProvider = Provider.family<bool, PlusFeature>((ref, feature) {
  if (!gatedFeatures.contains(feature)) return true;
  return ref.watch(plusEntitledProvider);
});
