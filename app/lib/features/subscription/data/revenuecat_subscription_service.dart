import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../domain/plus_subscription.dart';
import 'subscription_service.dart';

final Logger _log = Logger('SubscriptionService');

/// The platform name [revenueCatKeyFor] picks a key by.
///
/// Split out so tests can name a platform without a device; on the desktop VM
/// this answers `linux`, which has no key and therefore no store.
String currentStorePlatform() => kIsWeb ? 'web' : Platform.operatingSystem;

/// The handful of `rc.Purchases` statics this service calls.
///
/// Behind an interface because statics cannot be faked: without it every test
/// of the mapping and the error handling below would need a real platform
/// channel, which no unit test has. Production passes [SdkPurchasesApi] and
/// nothing changes.
abstract interface class PurchasesApi {
  /// Sets how loud the SDK is in the console.
  Future<void> setLogLevel(rc.LogLevel level);

  /// Starts the SDK with [configuration]. Must happen before anything else.
  Future<void> configure(rc.PurchasesConfiguration configuration);

  /// Registers [listener] for every customer info change the store reports.
  void addCustomerInfoUpdateListener(rc.CustomerInfoUpdateListener listener);

  /// Unregisters a listener added with [addCustomerInfoUpdateListener].
  void removeCustomerInfoUpdateListener(rc.CustomerInfoUpdateListener listener);

  /// Asks the store what this subscriber owns.
  Future<rc.CustomerInfo> getCustomerInfo();

  /// Asks the store for the configured offerings and their prices.
  Future<rc.Offerings> getOfferings();

  /// Opens the store's purchase sheet for [params].
  Future<rc.PurchaseResult> purchase(rc.PurchaseParams params);

  /// Restores whatever this store account already owns.
  Future<rc.CustomerInfo> restorePurchases();
}

/// [PurchasesApi] over the real `rc.Purchases` statics.
///
/// Deliberately nothing but forwarding: every decision the app makes lives in
/// [RevenueCatSubscriptionService], where a test can reach it.
class SdkPurchasesApi implements PurchasesApi {
  /// Creates the SDK-backed api.
  const SdkPurchasesApi();

  @override
  Future<void> setLogLevel(rc.LogLevel level) =>
      rc.Purchases.setLogLevel(level);

  @override
  Future<void> configure(rc.PurchasesConfiguration configuration) =>
      rc.Purchases.configure(configuration);

  @override
  void addCustomerInfoUpdateListener(rc.CustomerInfoUpdateListener listener) =>
      rc.Purchases.addCustomerInfoUpdateListener(listener);

  @override
  void removeCustomerInfoUpdateListener(
    rc.CustomerInfoUpdateListener listener,
  ) => rc.Purchases.removeCustomerInfoUpdateListener(listener);

  @override
  Future<rc.CustomerInfo> getCustomerInfo() => rc.Purchases.getCustomerInfo();

  @override
  Future<rc.Offerings> getOfferings() => rc.Purchases.getOfferings();

  @override
  Future<rc.PurchaseResult> purchase(rc.PurchaseParams params) =>
      rc.Purchases.purchase(params);

  @override
  Future<rc.CustomerInfo> restorePurchases() => rc.Purchases.restorePurchases();
}

/// [SubscriptionService] over RevenueCat's `purchases_flutter`.
///
/// One entitlement ([plusEntitlementId]), one anonymous subscriber, no login.
/// The SDK's own types never leave this file: everything is mapped onto the
/// plain objects in `plus_subscription.dart`.
class RevenueCatSubscriptionService implements SubscriptionService {
  /// Creates the service for [apiKey], identifying the subscriber as
  /// [appUserId].
  ///
  /// [appUserId] is the id the relay also authenticates against, so an
  /// entitlement bought here is the one the relay sees. Passing it means the
  /// subscriber is "identified" from RevenueCat's point of view even though
  /// the id is a random string the app made up — which is what allows
  /// [restorePurchases] to work without any account.
  ///
  /// [purchases] defaults to the real SDK; only tests pass anything else.
  RevenueCatSubscriptionService({
    required this.apiKey,
    required this.appUserId,
    this.purchases = const SdkPurchasesApi(),
  });

  /// The RevenueCat public SDK key of this platform.
  final String apiKey;

  /// The subscriber id, shared with the relay.
  final String appUserId;

  /// The store SDK, so a test can answer for it.
  final PurchasesApi purchases;

  final StreamController<PlusCustomerInfo> _updates =
      StreamController<PlusCustomerInfo>.broadcast();

  PlusCustomerInfo _latest = PlusCustomerInfo.none;
  rc.CustomerInfoUpdateListener? _listener;
  bool _configured = false;

  @override
  bool get isAvailable => true;

  @override
  PlusCustomerInfo get latest => _latest;

  @override
  Stream<PlusCustomerInfo> get customerInfo async* {
    yield _latest;
    yield* _updates.stream;
  }

  @override
  Future<void> configure() async {
    if (_configured) return;
    try {
      await purchases.setLogLevel(
        kReleaseMode ? rc.LogLevel.warn : rc.LogLevel.info,
      );
      await purchases.configure(
        rc.PurchasesConfiguration(apiKey)..appUserID = appUserId,
      );
      final listener = _emitFromSdk;
      _listener = listener;
      purchases.addCustomerInfoUpdateListener(listener);
      // Only now: a configure that failed at launch (no network, no Play
      // services) is tried again on the next call.
      _configured = true;
      _emit(fromCustomerInfo(await purchases.getCustomerInfo()));
    } on Object catch (e, st) {
      // A store that is unreachable at launch is normal (no network, an
      // emulator without Play services). The rider stays unentitled until the
      // next refresh; nothing else in the app depends on this succeeding.
      _log.warning('RevenueCat could not be configured', e, st);
    }
  }

  @override
  Future<PlusCustomerInfo> refresh() async {
    try {
      final info = fromCustomerInfo(await purchases.getCustomerInfo());
      _emit(info);
      return info;
    } on Object catch (e, st) {
      _log.info('customer info could not be refreshed', e, st);
      return _latest;
    }
  }

  @override
  Future<PlusOffering?> offerings() async {
    try {
      final offerings = await purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return null;
      return PlusOffering(
        id: current.identifier,
        packages: current.availablePackages
            .map(fromPackage)
            .toList(growable: false),
      );
    } on PlatformException catch (e) {
      throw _exceptionFor(e);
    } on Object catch (e) {
      throw SubscriptionException(
        SubscriptionFailure.unknown,
        'The store could not be asked for prices.',
        cause: e,
      );
    }
  }

  @override
  Future<PlusCustomerInfo> purchase(PlusPackage package) async {
    final native = package.native;
    if (native is! rc.Package) {
      throw const SubscriptionException(
        SubscriptionFailure.unknown,
        'This package did not come from the store.',
      );
    }
    try {
      final result = await purchases.purchase(
        rc.PurchaseParams.package(native),
      );
      final info = fromCustomerInfo(result.customerInfo);
      _emit(info);
      return info;
    } on PlatformException catch (e) {
      throw _exceptionFor(e);
    }
  }

  @override
  Future<PlusCustomerInfo> restorePurchases() async {
    try {
      final info = fromCustomerInfo(await purchases.restorePurchases());
      _emit(info);
      return info;
    } on PlatformException catch (e) {
      throw _exceptionFor(e);
    }
  }

  @override
  void dispose() {
    final listener = _listener;
    if (listener != null) {
      purchases.removeCustomerInfoUpdateListener(listener);
    }
    _listener = null;
    unawaited(_updates.close());
  }

  void _emitFromSdk(rc.CustomerInfo info) => _emit(fromCustomerInfo(info));

  void _emit(PlusCustomerInfo info) {
    _latest = info;
    if (!_updates.isClosed) _updates.add(info);
  }

  /// Maps a RevenueCat error onto the app's own failure kinds.
  static SubscriptionException _exceptionFor(PlatformException e) {
    final rc.PurchasesErrorCode code;
    try {
      code = rc.PurchasesErrorHelper.getErrorCode(e);
    } on Object {
      return SubscriptionException(
        SubscriptionFailure.unknown,
        e.message ?? 'The store reported an error.',
        cause: e,
      );
    }
    final failure = switch (code) {
      rc.PurchasesErrorCode.purchaseCancelledError =>
        SubscriptionFailure.cancelled,
      rc.PurchasesErrorCode.purchaseNotAllowedError =>
        SubscriptionFailure.notAllowed,
      rc.PurchasesErrorCode.storeProblemError ||
      rc.PurchasesErrorCode.networkError ||
      rc.PurchasesErrorCode.offlineConnectionError ||
      rc.PurchasesErrorCode.productNotAvailableForPurchaseError =>
        SubscriptionFailure.storeProblem,
      _ => SubscriptionFailure.unknown,
    };
    return SubscriptionException(
      failure,
      e.message ?? 'The store reported ${code.name}.',
      cause: e,
    );
  }
}

/// Maps RevenueCat's customer info onto [PlusCustomerInfo].
///
/// Public so a test can prove the entitlement mapping without a store.
PlusCustomerInfo fromCustomerInfo(rc.CustomerInfo info) {
  final entitlement = info.entitlements.active[plusEntitlementId];
  return PlusCustomerInfo(
    entitled: entitlement != null,
    expiresAt: _parseDate(entitlement?.expirationDate),
    willRenew: entitlement?.willRenew ?? false,
    managementUrl: info.managementURL,
    productIdentifier: entitlement?.productIdentifier,
  );
}

/// Maps one RevenueCat package onto [PlusPackage].
PlusPackage fromPackage(rc.Package package) {
  final product = package.storeProduct;
  final intro = product.introductoryPrice;
  return PlusPackage(
    id: package.identifier,
    title: product.title,
    priceString: product.priceString,
    period: _periodOf(package.packageType),
    introOffer: intro == null
        ? null
        : PlusIntroOffer(
            priceString: intro.priceString,
            periodUnit: intro.periodUnit.name,
            periodCount: intro.periodNumberOfUnits,
            isFree: intro.price == 0,
          ),
    native: package,
  );
}

PlusPeriod _periodOf(rc.PackageType type) => switch (type) {
  rc.PackageType.weekly => PlusPeriod.weekly,
  rc.PackageType.monthly => PlusPeriod.monthly,
  rc.PackageType.twoMonth => PlusPeriod.twoMonthly,
  rc.PackageType.threeMonth => PlusPeriod.threeMonthly,
  rc.PackageType.sixMonth => PlusPeriod.sixMonthly,
  rc.PackageType.annual => PlusPeriod.annual,
  rc.PackageType.lifetime => PlusPeriod.lifetime,
  rc.PackageType.custom || rc.PackageType.unknown => PlusPeriod.other,
};

DateTime? _parseDate(String? iso) =>
    iso == null ? null : DateTime.tryParse(iso)?.toLocal();
