import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../core/plus/plus_gate.dart';
import '../../integrations/rwgps/data/rwgps_providers.dart';
import '../../integrations/strava/data/strava_providers.dart';

/// The Plus features this build can actually deliver, in paywall order.
///
/// `gatedFeatures` says what Plus *covers*; this says what it can *sell*
/// right now. A partner integration without its client id cannot connect, and
/// the connections screen already hides it - so offering it on the paywall
/// would charge for something the rider then cannot find. App Review rejects
/// exactly that (guideline 2.1), and a rider would be right to ask for a
/// refund. Once the id is in the build's env file, the row comes back by
/// itself.
final offeredPlusFeaturesProvider = Provider<List<PlusFeature>>((ref) {
  bool deliverable(PlusFeature feature) => switch (feature) {
    PlusFeature.stravaConnection => ref.watch(stravaConfiguredProvider),
    PlusFeature.rwgpsConnection => ref.watch(rwgpsConfiguredProvider),
    PlusFeature.aiAssistant || PlusFeature.linkSharing => true,
    // Forecasts come through the relay; a build without one has none.
    PlusFeature.weather => ref.watch(effectiveConfigProvider).hasApi,
  };
  return [
    for (final feature in PlusFeature.values)
      if (gatedFeatures.contains(feature) && deliverable(feature)) feature,
  ];
});
