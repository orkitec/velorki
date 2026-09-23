import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../app/app_config.dart';
import '../../../core/plus/plus_gate.dart';
import '../data/subscription_service.dart';
import '../domain/plus_subscription.dart';

final Logger _log = Logger('Subscription');

/// What the subscription is doing right now, so buttons can show a spinner
/// and refuse a second tap.
enum PlusAction {
  /// Nothing in flight.
  none,

  /// A store purchase sheet is open.
  purchasing,

  /// The store is being asked what this account already owns.
  restoring,
}

/// The paywall's and the settings tile's shared state machine.
///
/// Both screens buy and restore through this one notifier, so a purchase
/// started in the paywall and a restore started in settings can never run at
/// the same time, and both write the entitlement the same way.
class SubscriptionController extends Notifier<PlusAction> {
  @override
  PlusAction build() => PlusAction.none;

  /// Buys [package].
  ///
  /// Returns `null` when the rider dismissed the store sheet — that is not an
  /// error and needs no message. Every other failure throws
  /// [SubscriptionException].
  Future<PlusCustomerInfo?> purchase(PlusPackage package) async {
    if (state != PlusAction.none) return null;
    state = PlusAction.purchasing;
    try {
      final info = await ref
          .read(subscriptionServiceProvider)
          .purchase(package);
      _apply(info);
      return info;
    } on SubscriptionException catch (e) {
      if (e.failure == SubscriptionFailure.cancelled) return null;
      rethrow;
    } finally {
      state = PlusAction.none;
    }
  }

  /// Restores what this store account already owns.
  ///
  /// There is no login to do first: the store knows the account, and Velorki
  /// has no accounts of its own. Returns the info the store answered with, so
  /// the caller can tell "restored" from "there was nothing to restore".
  Future<PlusCustomerInfo> restore() async {
    if (state != PlusAction.none) {
      return ref.read(subscriptionServiceProvider).latest;
    }
    state = PlusAction.restoring;
    try {
      final info = await ref
          .read(subscriptionServiceProvider)
          .restorePurchases();
      _apply(info);
      return info;
    } finally {
      state = PlusAction.none;
    }
  }

  void _apply(PlusCustomerInfo info) {
    ref.read(plusEntitledProvider.notifier).value = info.entitled;
  }
}

/// The purchase and restore state machine.
final subscriptionControllerProvider =
    NotifierProvider<SubscriptionController, PlusAction>(
      SubscriptionController.new,
    );

/// The current offering, fetched once per screen.
///
/// `null` data means the store has no offering configured, which is a
/// misconfiguration the paywall has to say something about; an error means
/// the store could not be asked at all.
final plusOfferingProvider = FutureProvider<PlusOffering?>(
  (ref) => ref.watch(subscriptionServiceProvider).offerings(),
);

/// Starts the store SDK and keeps [plusEntitledProvider] in step with it.
///
/// Called once from `bootstrap()` with the app's container. Configuring is
/// awaited nowhere: the first frame must not wait for a store round trip, and
/// every gated screen reacts to the entitlement when it arrives.
///
/// A build with [AppConfig.stubsPlus] never asks a store: the entitlement is
/// granted here and nothing later takes it away, so no paywall opens.
void startSubscriptions(ProviderContainer container) {
  if (container.read(appConfigProvider).stubsPlus) {
    _log.warning(
      'VELORKI_PLUS_STUB is set, no RevenueCat key is, not a release: '
      'Velorki Plus is treated as active in this build',
    );
    container.read(plusEntitledProvider.notifier).value = true;
    return;
  }

  container.listen<AsyncValue<PlusCustomerInfo>>(plusCustomerInfoProvider, (
    previous,
    next,
  ) {
    final info = next.value;
    if (info == null) return;
    final entitled = info.entitled;
    if (container.read(plusEntitledProvider) == entitled) return;
    _log.info('Velorki Plus is ${entitled ? 'active' : 'not active'}');
    container.read(plusEntitledProvider.notifier).value = entitled;
  }, fireImmediately: true);

  unawaited(container.read(subscriptionServiceProvider).configure());
}
