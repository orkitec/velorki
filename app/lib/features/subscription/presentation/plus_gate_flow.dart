import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/plus/plus_gate.dart';
import '../application/plus_access.dart';

/// Shows the paywall before [feature] when Plus is known to be missing, and
/// answers whether to go on to the feature.
///
/// Known missing, the paywall opens first and the answer is whether the
/// rider left it subscribed. Granted, or not known yet, the answer is `true`
/// straight away: the feature opens and the relay's own check has the last
/// word, rather than the rider waiting on a store that may not answer.
Future<bool> passPlusGate(
  BuildContext context,
  WidgetRef ref,
  PlusFeature feature,
) async {
  if (ref.read(plusAccessProvider(feature)) != PlusAccess.missing) return true;
  await GoRouter.of(context).push<void>(paywallRoute);
  if (!context.mounted) return false;
  return ref.read(plusFeatureProvider(feature));
}
