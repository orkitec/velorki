import 'dart:async';

import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';

/// A [SubscriptionService] whose answers the test dictates.
///
/// Stands in for RevenueCat everywhere: no platform channel, no store, and
/// every failure the real SDK can report is one field away.
class FakeSubscriptionService implements SubscriptionService {
  /// Creates a fake service.
  FakeSubscriptionService({
    this.isAvailable = true,
    PlusCustomerInfo? initial,
    this.offering,
    this.offeringsFailure,
    this.purchaseFailure,
    this.purchased,
    this.restored,
  }) : _latest = initial ?? PlusCustomerInfo.none;

  @override
  final bool isAvailable;

  /// What [offerings] answers.
  PlusOffering? offering;

  /// Thrown by [offerings] when set.
  SubscriptionException? offeringsFailure;

  /// Thrown by [purchase] when set.
  SubscriptionException? purchaseFailure;

  /// What a successful [purchase] answers.
  PlusCustomerInfo? purchased;

  /// What [restorePurchases] answers.
  PlusCustomerInfo? restored;

  /// Every package that was bought, in order.
  final List<PlusPackage> purchases = <PlusPackage>[];

  /// How often [restorePurchases] ran.
  int restores = 0;

  /// How often [configure] ran.
  int configures = 0;

  PlusCustomerInfo _latest;
  final StreamController<PlusCustomerInfo> _updates =
      StreamController<PlusCustomerInfo>.broadcast();

  @override
  PlusCustomerInfo get latest => _latest;

  @override
  Stream<PlusCustomerInfo> get customerInfo async* {
    yield _latest;
    yield* _updates.stream;
  }

  /// Pushes [info] as if the store had reported a change.
  void emit(PlusCustomerInfo info) {
    _latest = info;
    _updates.add(info);
  }

  @override
  Future<void> configure() async => configures++;

  @override
  Future<PlusCustomerInfo> refresh() async => _latest;

  @override
  Future<PlusOffering?> offerings() async {
    if (offeringsFailure != null) throw offeringsFailure!;
    return offering;
  }

  @override
  Future<PlusCustomerInfo> purchase(PlusPackage package) async {
    purchases.add(package);
    if (purchaseFailure != null) throw purchaseFailure!;
    final info = purchased ?? const PlusCustomerInfo(entitled: true);
    emit(info);
    return info;
  }

  @override
  Future<PlusCustomerInfo> restorePurchases() async {
    restores++;
    final info = restored ?? _latest;
    emit(info);
    return info;
  }

  @override
  void dispose() => unawaited(_updates.close());
}

/// A monthly package with a seven-day free trial, as the paywall renders it.
const PlusPackage trialMonthly = PlusPackage(
  id: r'$rc_monthly',
  title: 'Velorki Plus',
  priceString: '€2.99',
  period: PlusPeriod.monthly,
  introOffer: PlusIntroOffer(
    priceString: '€0.00',
    periodUnit: 'day',
    periodCount: 7,
    isFree: true,
  ),
);

/// An annual package without any introductory offer.
const PlusPackage plainAnnual = PlusPackage(
  id: r'$rc_annual',
  title: 'Velorki Plus',
  priceString: '€24.99',
  period: PlusPeriod.annual,
);

/// The offering both packages belong to.
const PlusOffering defaultOffering = PlusOffering(
  id: 'default',
  packages: <PlusPackage>[trialMonthly, plainAnnual],
);
