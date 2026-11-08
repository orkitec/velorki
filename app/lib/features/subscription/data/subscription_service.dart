import 'dart:async';

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../domain/plus_subscription.dart';

/// The store subscription, behind one small interface.
///
/// Everything above this line — the paywall, the settings tile, the gates —
/// works in terms of [PlusCustomerInfo] and [PlusPackage]. Below it there are
/// exactly two implementations: `RevenueCatSubscriptionService` for builds
/// that carry a RevenueCat key, and [NoopSubscriptionService] for forks, for
/// CI and for the desktop test VM. This file knows only the second one: the
/// store SDK is reached from `main.dart` alone, so a build without it (the
/// F-Droid flavour, `main_fdroid.dart`) never compiles the plugin in.
abstract interface class SubscriptionService {
  /// Whether this build can actually sell anything.
  ///
  /// `false` means there is no RevenueCat key: the paywall then explains that
  /// Plus is unavailable in this build instead of showing packages.
  bool get isAvailable;

  /// The latest known customer info, without waiting.
  PlusCustomerInfo get latest;

  /// The customer info, starting with [latest] once the store has answered
  /// and then every update the store SDK reports (a purchase, a restore, an
  /// expiry, a refund). Nothing comes before the store's first answer, so a
  /// listener can tell "not known yet" from "nothing owned".
  Stream<PlusCustomerInfo> get customerInfo;

  /// Starts the store SDK. Called once from `bootstrap()`.
  ///
  /// Never throws: a store that cannot be reached at launch must not stop the
  /// app from starting. Failures leave [latest] at [PlusCustomerInfo.none].
  Future<void> configure();

  /// Asks the store for the customer info again.
  Future<PlusCustomerInfo> refresh();

  /// The country of the store account the phone buys from (ISO 3166-1
  /// alpha-3, `CHN` for China's App Store), or `null` when there is no store
  /// or it cannot say. Not the phone's region: App Review in China uses a
  /// Chinese account on any phone.
  ///
  /// Never throws.
  Future<String?> storeCountry();

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
  Future<String?> storeCountry() async => null;

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

/// The platform name [revenueCatKeyFor] picks a key by.
///
/// Split out so tests can name a platform without a device; on the desktop VM
/// this answers `linux`, which has no key and therefore no store.
String currentStorePlatform() => kIsWeb ? 'web' : Platform.operatingSystem;

/// The RevenueCat public SDK key for the platform this build runs on, or `''`
/// when there is none.
String revenueCatKeyFor(AppConfig config, {required String platform}) =>
    switch (platform) {
      'android' => config.revenueCatKeyAndroid,
      'ios' || 'macos' => config.revenueCatKeyIos,
      _ => '',
    };

/// The subscription service this build runs with: none of its own.
///
/// `main.dart` overrides this with the RevenueCat service wherever this build
/// carries a key (`storeSubscriptionOverride`); nothing else does, so neither
/// the F-Droid flavour nor a widget test reaches the store SDK. Kept alive for
/// the process: the SDK is configured once and its customer info listener has
/// to outlive every screen.
final subscriptionServiceProvider = Provider<SubscriptionService>(
  (ref) => const NoopSubscriptionService(),
);

/// The store account's country, as [SubscriptionService.storeCountry] says;
/// asked once per process.
final storeCountryProvider = FutureProvider<String?>(
  (ref) => ref.watch(subscriptionServiceProvider).storeCountry(),
);

/// The customer info as a stream, for the paywall, the settings tile and
/// `plusAccessProvider`. Loading until the store has answered.
final plusCustomerInfoProvider = StreamProvider<PlusCustomerInfo>(
  (ref) => ref.watch(subscriptionServiceProvider).customerInfo,
);
