import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/plus/plus_gate.dart';
import '../data/subscription_service.dart';

/// What is known about the rider's right to a Plus feature.
enum PlusAccess {
  /// The feature may be used: it is free, or Plus is active.
  granted,

  /// The store has answered and Plus is not active.
  missing,

  /// Nobody can tell yet: the store has not answered (it may never, offline
  /// at launch), or this build has no store to ask. The relay decides.
  unknown,
}

/// Whether [PlusFeature] may be used, and whether a "no" is a known one.
///
/// [plusFeatureProvider] is false both before the store answers and when it
/// answered "nothing owned"; a screen that sends the rider to the paywall
/// before they try must only do so on the second.
final plusAccessProvider = Provider.family<PlusAccess, PlusFeature>((
  ref,
  feature,
) {
  if (ref.watch(plusFeatureProvider(feature))) return PlusAccess.granted;
  if (!ref.watch(subscriptionServiceProvider).isAvailable) {
    return PlusAccess.unknown;
  }
  return ref.watch(plusCustomerInfoProvider).hasValue
      ? PlusAccess.missing
      : PlusAccess.unknown;
});
