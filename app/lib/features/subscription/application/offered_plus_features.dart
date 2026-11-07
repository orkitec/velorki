import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../core/plus/plus_gate.dart';

/// The Plus features this build can actually deliver, in paywall order; empty
/// where it does not offer Plus at all ([plusOfferedProvider]).
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
  if (!ref.watch(plusOfferedProvider)) return const [];
  return [
    for (final feature in PlusFeature.values)
      if (gatedFeatures.contains(feature) && deliverable(feature)) feature,
  ];
});

/// Whether [feature] is offered in this build at all — which is what every
/// entry point for it asks before drawing itself.
///
/// Not the same question as [plusFeatureProvider], which is whether the rider
/// holds it: a rider without Plus is shown the feature and what it costs, a
/// build that does not offer it shows nothing.
final plusFeatureOfferedProvider = Provider.family<bool, PlusFeature>(
  (ref, feature) => ref.watch(offeredPlusFeaturesProvider).contains(feature),
);
