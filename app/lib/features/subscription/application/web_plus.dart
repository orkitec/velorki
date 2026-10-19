import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../../core/plus/plus_gate.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../sync/application/cloud_sync_controller.dart';

/// Whether this browser build can sign into iCloud or Google (Settings →
/// Sync with offers one), which is what lets the rider use Plus bought in a
/// phone app here ([WebPlus]); the paywall then says how.
final webCloudSignInProvider = Provider<bool>(
  (ref) => kIsWeb && ref.watch(offeredSyncServicesProvider).isNotEmpty,
);

/// The Plus token this browser holds, in memory only: what `POST /plus/web`
/// gave for the rider's cloud sign-in. While it holds one, the relay client
/// sends it in place of the app user id and Plus counts as active; it lets
/// go at expiry, and the sign-in asks again.
///
/// The browser never makes a RevenueCat id of its own: the relay finds the
/// ids the rider's apps wrote into that cloud.
class WebPlus extends Notifier<PlusWebToken?> {
  Timer? _expiry;

  @override
  PlusWebToken? build() {
    ref.onDispose(() => _expiry?.cancel());
    return null;
  }

  /// Trades the cloud's [cloudToken] for a Plus token and holds it. Throws
  /// [RelayException]: `not_entitled` with a reason (`cloud_auth`,
  /// `no_devices`, `not_subscribed`) when there is no Plus to be had, and
  /// leaves what it held as it was; an `IntegrationException` in a build
  /// without a relay.
  Future<PlusWebToken> signIn(PlusWebService service, String cloudToken) async {
    final relay = requireRelay(ref);
    final plus = await relay.plusWeb(service: service, token: cloudToken);
    _expiry?.cancel();
    final left = plus.expiresAt.difference(DateTime.now());
    if (left <= Duration.zero) {
      forget();
      return plus;
    }
    _expiry = Timer(left, forget);
    state = plus;
    ref.read(plusEntitledProvider.notifier).value = true;
    return plus;
  }

  /// Lets go of the token: signed out, or expired.
  void forget() {
    _expiry?.cancel();
    _expiry = null;
    if (state == null) return;
    state = null;
    ref.read(plusEntitledProvider.notifier).value = false;
  }
}

/// [WebPlus].
final webPlusProvider = NotifierProvider<WebPlus, PlusWebToken?>(WebPlus.new);
