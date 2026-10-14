import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../core/plus/plus_gate.dart';

/// The Plus features this build can actually deliver, in paywall order.
///
/// `gatedFeatures` says what Plus *covers*; this says what it can *sell*
/// right now. A feature the build cannot deliver - forecasts without a relay -
/// would charge for something the rider then cannot find. App Review rejects
/// exactly that (guideline 2.1), and a rider would be right to ask for a
/// refund.
final offeredPlusFeaturesProvider = Provider<List<PlusFeature>>((ref) {
  bool deliverable(PlusFeature feature) => switch (feature) {
    PlusFeature.aiAssistant || PlusFeature.linkSharing => true,
    // Forecasts come through the relay; a build without one has none.
    PlusFeature.weather => ref.watch(effectiveConfigProvider).hasApi,
  };
  return [
    for (final feature in PlusFeature.values)
      if (gatedFeatures.contains(feature) && deliverable(feature)) feature,
  ];
});
