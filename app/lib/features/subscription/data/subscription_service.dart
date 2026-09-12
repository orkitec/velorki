import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../core/plus/app_user_id.dart';
import '../domain/plus_subscription.dart';
import 'revenuecat_subscription_service.dart';

/// The store subscription, behind one small interface.
///
/// Everything above this line — the paywall, the settings tile, the gates —
/// works in terms of [PlusCustomerInfo] and [PlusPackage]. Below it there are
/// exactly two implementations: [RevenueCatSubscriptionService] for builds
/// that carry a RevenueCat key, and [NoopSubscriptionService] for forks, for
/// CI and for the desktop test VM.
abstract interface class SubscriptionService {
  /// Whether this build can actually sell anything.
  ///
  /// `false` means there is no RevenueCat key: the paywall then explains that
  /// Plus is unavailable in this build instead of showing packages.
  bool get isAvailable;

  /// The latest known customer info, without waiting.
  PlusCustomerInfo get latest;

  /// The customer info, starting with [latest] and then every update the
  /// store SDK reports (a purchase, a restore, an expiry, a refund).
  Stream<PlusCustomerInfo> get customerInfo;

  /// Starts the store SDK. Called once from `bootstrap()`.
  ///
  /// Never throws: a store that cannot be reached at launch must not stop the
  /// app from starting. Failures leave [latest] at [PlusCustomerInfo.none].
  Future<void> configure();

  /// Asks the store for the customer info again.
  Future<PlusCustomerInfo> refresh();

  /// The current offering, or `null` when the store has none configured.
  ///
  /// Throws [SubscriptionException] when the store could not be asked.
  Future<PlusOffering?> offerings();

  /// Buys [package].
  ///
  /// Throws [SubscriptionException] with [SubscriptionFailure.cancelled] when
  /// the rider dismissed the store sheet, which callers usually ignore.
  Future<PlusCustomerInfo> purchase(PlusPackage package);

  /// Restores whatever this store account already owns.
  ///
  /// Works without any login — which is exactly why it has to exist: Velorki
  /// has no accounts, so a reinstall gets its subscription back through the
  /// store and nothing else.
  Future<PlusCustomerInfo> restorePurchases();

  /// Releases the SDK listeners.
  void dispose();
}

/// The subscription service of a build without a RevenueCat key.
///
/// A fork that has not set `VELORKI_REVENUECAT_KEY_ANDROID` or
/// `..._IOS` still compiles, still runs and still shows the paywall — the
/// paywall just says that Plus cannot be bought here. Nothing throws except
/// [purchase], which cannot do anything sensible.
class NoopSubscriptionService implements SubscriptionService {
  /// Creates the no-op service.
  const NoopSubscriptionService();

  @override
  bool get isAvailable => false;

  @override
  PlusCustomerInfo get latest => PlusCustomerInfo.none;

  @override
  Stream<PlusCustomerInfo> get customerInfo =>
      Stream<PlusCustomerInfo>.value(PlusCustomerInfo.none);

  @override
  Future<void> configure() async {}

  @override
  Future<PlusCustomerInfo> refresh() async => PlusCustomerInfo.none;

  @override
  Future<PlusOffering?> offerings() async => null;

  @override
  Future<PlusCustomerInfo> purchase(PlusPackage package) async =>
      throw const SubscriptionException(
        SubscriptionFailure.unavailable,
        'This build of Velorki has no store configured.',
      );

  @override
  Future<PlusCustomerInfo> restorePurchases() async => PlusCustomerInfo.none;

  @override
  void dispose() {}
}

/// The RevenueCat public SDK key for the platform this build runs on, or `''`
/// when there is none.
String revenueCatKeyFor(AppConfig config, {required String platform}) =>
    switch (platform) {
      'android' => config.revenueCatKeyAndroid,
      'ios' || 'macos' => config.revenueCatKeyIos,
      _ => '',
    };

/// The subscription service this build runs with.
///
/// Kept alive for the process: the SDK is configured once and its customer
/// info listener has to outlive every screen. Widget tests override this with
/// a fake and never touch a platform channel.
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final config = ref.watch(appConfigProvider);
  final key = revenueCatKeyFor(config, platform: currentStorePlatform());
  if (key.isEmpty) return const NoopSubscriptionService();
  final service = RevenueCatSubscriptionService(
    apiKey: key,
    // The same id the relay authenticates against, so RevenueCat's customer
    // and the `Authorization: Bearer <app_user_id>` the app sends are one
    // and the same subscriber.
    appUserId: ref.watch(appUserIdProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// The customer info as a stream, for the paywall and the settings tile.
final plusCustomerInfoProvider = StreamProvider<PlusCustomerInfo>(
  (ref) => ref.watch(subscriptionServiceProvider).customerInfo,
);
