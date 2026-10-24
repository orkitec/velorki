import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../core/plus/plus_gate.dart';
import '../../sync/application/cloud_sync_controller.dart';
import '../../sync/application/web_plus_devices.dart';
import 'subscription_controller.dart';

/// Whether this browser build can sign into iCloud or Google (Settings →
/// Sync with offers one), which is what lets the rider use Plus bought in a
/// phone app here; the paywall then says how.
final webCloudSignInProvider = Provider<bool>(
  (ref) => kIsWeb && ref.watch(offeredSyncServicesProvider).isNotEmpty,
);

/// Starts Plus in the browser, which has no store: the RevenueCat id of a
/// phone app syncing with the same cloud ([webPlusDeviceProvider]) is what
/// the relay client sends, and Plus is active while that app's store last
/// said so. The relay checks the id on every call, as for the apps.
///
/// Called once from `bootstrap_web.dart` in place of [startSubscriptions],
/// which still runs for a build with [AppConfig.stubsPlus].
void startWebPlus(ProviderContainer container) {
  if (container.read(appConfigProvider).stubsPlus) {
    startSubscriptions(container);
    return;
  }
  container.listen<PlusDeviceSeen?>(webPlusDeviceProvider, (_, device) {
    container.read(plusEntitledProvider.notifier).value =
        device?.entitled ?? false;
  }, fireImmediately: true);
}
