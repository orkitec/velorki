import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:velorki/features/subscription/data/revenuecat_subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';

/// A [PurchasesApi] the test answers for.
///
/// Stands in for the RevenueCat statics: every call is recorded, every answer
/// is a field, and every failure is one `...Error` away. No platform channel
/// is involved, so these tests run on the desktop VM like any other.
class FakePurchasesApi implements PurchasesApi {
  /// Creates the fake, answering [customerInfo] until told otherwise.
  FakePurchasesApi({rc.CustomerInfo? customerInfo, this.offeringsResult})
    : customerInfo = customerInfo ?? customerInfoWith();

  /// What [getCustomerInfo] answers.
  rc.CustomerInfo customerInfo;

  /// What [getOfferings] answers; an empty [rc.Offerings] when left null.
  rc.Offerings? offeringsResult;

  /// What a successful [purchase] reports back; [customerInfo] when null.
  rc.CustomerInfo? purchasedInfo;

  /// What a successful [restorePurchases] reports back; [customerInfo] when
  /// null.
  rc.CustomerInfo? restoredInfo;

  /// Thrown by [configure] when set, as an unreachable store would.
  Object? configureError;

  /// Thrown by [getCustomerInfo] when set.
  Object? customerInfoError;

  /// Thrown by [getOfferings] when set.
  Object? offeringsError;

  /// Thrown by [purchase] when set.
  Object? purchaseError;

  /// Thrown by [restorePurchases] when set.
  Object? restoreError;

  /// Every log level that was set, in order.
  final List<rc.LogLevel> logLevels = <rc.LogLevel>[];

  /// Every configuration the service handed over, in order.
  final List<rc.PurchasesConfiguration> configurations =
      <rc.PurchasesConfiguration>[];

  /// The listeners that are registered right now.
  final List<rc.CustomerInfoUpdateListener> listeners =
      <rc.CustomerInfoUpdateListener>[];

  /// Every purchase the service asked for, in order.
  final List<rc.PurchaseParams> purchases = <rc.PurchaseParams>[];

  /// How often [getCustomerInfo] ran.
  int customerInfoCalls = 0;

  /// How often [restorePurchases] ran.
  int restoreCalls = 0;

  /// Reports [info] to every registered listener, as the SDK does after a
  /// renewal, a refund or a purchase made on another device.
  void reportUpdate(rc.CustomerInfo info) {
    for (final listener in List<rc.CustomerInfoUpdateListener>.of(listeners)) {
      listener(info);
    }
  }

  @override
  Future<void> setLogLevel(rc.LogLevel level) async => logLevels.add(level);

  @override
  Future<void> configure(rc.PurchasesConfiguration configuration) async {
    configurations.add(configuration);
    if (configureError != null) throw configureError!;
  }

  @override
  void addCustomerInfoUpdateListener(rc.CustomerInfoUpdateListener listener) =>
      listeners.add(listener);

  @override
  void removeCustomerInfoUpdateListener(
    rc.CustomerInfoUpdateListener listener,
  ) => listeners.remove(listener);

  @override
  Future<rc.CustomerInfo> getCustomerInfo() async {
    customerInfoCalls++;
    if (customerInfoError != null) throw customerInfoError!;
    return customerInfo;
  }

  @override
  Future<rc.Offerings> getOfferings() async {
    if (offeringsError != null) throw offeringsError!;
    return offeringsResult ?? const rc.Offerings(<String, rc.Offering>{});
  }

  @override
  Future<rc.PurchaseResult> purchase(rc.PurchaseParams params) async {
    purchases.add(params);
    if (purchaseError != null) throw purchaseError!;
    return rc.PurchaseResult(
      purchasedInfo ?? customerInfo,
      const rc.StoreTransaction('txn', 'plus_monthly', '2026-01-01T00:00:00Z'),
    );
  }

  @override
  Future<rc.CustomerInfo> restorePurchases() async {
    restoreCalls++;
    if (restoreError != null) throw restoreError!;
    return restoredInfo ?? customerInfo;
  }
}

/// An SDK entitlement, active by default because that is the interesting case.
rc.EntitlementInfo entitlementInfo({
  String identifier = plusEntitlementId,
  bool isActive = true,
  bool willRenew = true,
  String productIdentifier = 'plus_monthly',
  String? expirationDate,
}) => rc.EntitlementInfo(
  identifier,
  isActive,
  willRenew,
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z',
  productIdentifier,
  false,
  expirationDate: expirationDate,
);

/// SDK customer info whose active entitlements are [active].
///
/// All the fields the app never reads are filled with plausible constants, so
/// a test only has to name the entitlement it cares about.
rc.CustomerInfo customerInfoWith({
  List<rc.EntitlementInfo> active = const <rc.EntitlementInfo>[],
  String? managementURL,
}) {
  final byId = <String, rc.EntitlementInfo>{
    for (final entitlement in active) entitlement.identifier: entitlement,
  };
  return rc.CustomerInfo(
    rc.EntitlementInfos(byId, byId),
    const <String, String?>{},
    const <String>[],
    const <String>[],
    const <rc.StoreTransaction>[],
    '2026-01-01T00:00:00Z',
    'anonymous',
    const <String, String?>{},
    '2026-01-01T00:00:00Z',
    managementURL: managementURL,
  );
}

/// An SDK package, monthly and without an introductory offer by default.
rc.Package packageInfo({
  String identifier = r'$rc_monthly',
  rc.PackageType packageType = rc.PackageType.monthly,
  String title = 'Velorki Plus',
  String priceString = '€2.99',
  double price = 2.99,
  rc.IntroductoryPrice? introductoryPrice,
}) => rc.Package(
  identifier,
  packageType,
  rc.StoreProduct(
    'plus_monthly',
    'Everything Velorki can do',
    title,
    price,
    priceString,
    'EUR',
    introductoryPrice: introductoryPrice,
  ),
  const rc.PresentedOfferingContext('default', null, null),
);

/// An SDK offering holding [packages], named [identifier].
rc.Offering offeringInfo(
  List<rc.Package> packages, {
  String identifier = 'default',
}) => rc.Offering(
  identifier,
  'The default offering',
  const <String, Object>{},
  packages,
);

/// A [PlatformException] carrying the RevenueCat error [code].
///
/// The SDK encodes its error code as the stringified index of
/// [rc.PurchasesErrorCode], which is what `PurchasesErrorHelper.getErrorCode`
/// parses back out — so that is what a test has to build.
PlatformException storeError(rc.PurchasesErrorCode code, {String? message}) =>
    PlatformException(
      code: '${rc.PurchasesErrorCode.values.indexOf(code)}',
      message: message,
    );
