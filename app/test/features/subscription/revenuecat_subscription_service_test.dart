import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:velorki/features/subscription/data/revenuecat_subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';

import 'support/fake_purchases_api.dart';

RevenueCatSubscriptionService _service(FakePurchasesApi api) {
  final service = RevenueCatSubscriptionService(
    apiKey: 'goog_key',
    appUserId: 'rider-42',
    purchases: api,
  );
  addTearDown(service.dispose);
  return service;
}

/// The exception thrown by [body], which every failure test asserts on.
Future<SubscriptionException> _failureOf(Future<void> Function() body) async {
  try {
    await body();
  } on SubscriptionException catch (e) {
    return e;
  }
  fail('expected a SubscriptionException');
}

void main() {
  group('fromCustomerInfo', () {
    test('an active plus entitlement is what "entitled" means', () {
      final info = fromCustomerInfo(
        customerInfoWith(
          active: [
            entitlementInfo(
              expirationDate: '2026-03-01T12:00:00Z',
              productIdentifier: 'plus_annual',
            ),
          ],
          managementURL: 'https://play.google.com/store/account/subscriptions',
        ),
      );

      expect(info.entitled, isTrue);
      expect(info.expiresAt, DateTime.utc(2026, 3, 1, 12).toLocal());
      expect(info.expiresAt!.isUtc, isFalse);
      expect(info.willRenew, isTrue);
      expect(
        info.managementUrl,
        'https://play.google.com/store/account/subscriptions',
      );
      expect(info.productIdentifier, 'plus_annual');
    });

    test('a subscription that was cancelled but still runs does not renew', () {
      final info = fromCustomerInfo(
        customerInfoWith(
          active: [
            entitlementInfo(
              willRenew: false,
              expirationDate: '2026-03-01T12:00:00Z',
            ),
          ],
        ),
      );

      expect(info.entitled, isTrue);
      expect(info.willRenew, isFalse);
    });

    test('somebody else\'s entitlement does not unlock Plus', () {
      final info = fromCustomerInfo(
        customerInfoWith(active: [entitlementInfo(identifier: 'pro')]),
      );

      expect(info, PlusCustomerInfo.none);
    });

    test('no entitlement at all reads as nobody has bought anything', () {
      expect(fromCustomerInfo(customerInfoWith()), PlusCustomerInfo.none);
    });

    test('a lifetime purchase has no expiry', () {
      final info = fromCustomerInfo(
        customerInfoWith(active: [entitlementInfo(willRenew: false)]),
      );

      expect(info.entitled, isTrue);
      expect(info.expiresAt, isNull);
    });

    test('an expiry date the store mangled is dropped, not thrown', () {
      final info = fromCustomerInfo(
        customerInfoWith(
          active: [entitlementInfo(expirationDate: 'whenever really')],
        ),
      );

      expect(info.entitled, isTrue);
      expect(info.expiresAt, isNull);
    });
  });

  group('fromPackage', () {
    test('title, price and identifier come straight from the store', () {
      final package = fromPackage(
        packageInfo(
          identifier: r'$rc_annual',
          packageType: rc.PackageType.annual,
          title: 'Velorki Plus (yearly)',
          priceString: '€24.99',
        ),
      );

      expect(package.id, r'$rc_annual');
      expect(package.title, 'Velorki Plus (yearly)');
      expect(package.priceString, '€24.99');
      expect(package.period, PlusPeriod.annual);
      expect(package.introOffer, isNull);
      expect(package.hasFreeTrial, isFalse);
    });

    test('every package type the store knows maps onto a period', () {
      const periods = <rc.PackageType, PlusPeriod>{
        rc.PackageType.weekly: PlusPeriod.weekly,
        rc.PackageType.monthly: PlusPeriod.monthly,
        rc.PackageType.twoMonth: PlusPeriod.twoMonthly,
        rc.PackageType.threeMonth: PlusPeriod.threeMonthly,
        rc.PackageType.sixMonth: PlusPeriod.sixMonthly,
        rc.PackageType.annual: PlusPeriod.annual,
        rc.PackageType.lifetime: PlusPeriod.lifetime,
        rc.PackageType.custom: PlusPeriod.other,
        rc.PackageType.unknown: PlusPeriod.other,
      };

      for (final entry in periods.entries) {
        expect(
          fromPackage(packageInfo(packageType: entry.key)).period,
          entry.value,
          reason: '${entry.key.name} should map to ${entry.value.name}',
        );
      }
      expect(periods.keys, containsAll(rc.PackageType.values));
    });

    test('a zero-price introductory phase is the free trial', () {
      final package = fromPackage(
        packageInfo(
          introductoryPrice: const rc.IntroductoryPrice(
            0,
            '€0.00',
            'P1W',
            1,
            rc.PeriodUnit.day,
            7,
          ),
        ),
      );

      expect(package.introOffer, isNotNull);
      expect(package.introOffer!.priceString, '€0.00');
      expect(package.introOffer!.periodUnit, 'day');
      expect(package.introOffer!.periodCount, 7);
      expect(package.introOffer!.isFree, isTrue);
      expect(package.hasFreeTrial, isTrue);
    });

    test('a cheap first month is an offer but not a free trial', () {
      final package = fromPackage(
        packageInfo(
          introductoryPrice: const rc.IntroductoryPrice(
            0.99,
            '€0.99',
            'P1M',
            1,
            rc.PeriodUnit.month,
            1,
          ),
        ),
      );

      expect(package.introOffer!.isFree, isFalse);
      expect(package.introOffer!.periodUnit, 'month');
      expect(package.hasFreeTrial, isFalse);
    });

    test('the SDK package is carried along so it can be bought again', () {
      final native = packageInfo();

      expect(fromPackage(native).native, same(native));
    });
  });

  group('configure', () {
    test('starts the SDK once, with the id the relay authenticates', () async {
      final api = FakePurchasesApi(
        customerInfo: customerInfoWith(active: [entitlementInfo()]),
      );
      final service = _service(api);

      await service.configure();

      expect(api.configurations, hasLength(1));
      expect(api.configurations.single.apiKey, 'goog_key');
      expect(api.configurations.single.appUserID, 'rider-42');
      expect(api.logLevels, hasLength(1));
      expect(api.listeners, hasLength(1));
      expect(service.latest.entitled, isTrue);
      expect(service.isAvailable, isTrue);
    });

    test('configuring a second time does nothing at all', () async {
      final api = FakePurchasesApi();
      final service = _service(api);

      await service.configure();
      await service.configure();

      expect(api.configurations, hasLength(1));
      expect(api.listeners, hasLength(1));
      expect(api.customerInfoCalls, 1);
    });

    test('a store that cannot be reached still lets the app start', () async {
      final api = FakePurchasesApi()
        ..configureError = PlatformException(code: '23', message: 'no store');
      final service = _service(api);

      await service.configure();

      expect(service.latest, PlusCustomerInfo.none);
      expect(api.listeners, isEmpty);

      // The store came back: the next configure is a real attempt.
      api.configureError = null;
      await service.configure();
      expect(api.listeners, hasLength(1));
    });

    test(
      'a store that cannot say what is owned leaves nobody entitled',
      () async {
        final api = FakePurchasesApi()
          ..customerInfoError = StateError('offline');
        final service = _service(api);

        await service.configure();

        expect(service.latest, PlusCustomerInfo.none);
        expect(api.customerInfoCalls, 1);
      },
    );
  });

  group('customerInfo', () {
    test('starts at what is known and then follows the store', () async {
      final api = FakePurchasesApi();
      final service = _service(api);
      await service.configure();

      final seen = <PlusCustomerInfo>[];
      final subscription = service.customerInfo.listen(seen.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      api.reportUpdate(customerInfoWith(active: [entitlementInfo()]));
      api.reportUpdate(customerInfoWith());
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(3));
      expect(seen[0], PlusCustomerInfo.none);
      expect(seen[1].entitled, isTrue);
      expect(seen[2].entitled, isFalse);
    });

    test('an update from the store also becomes the latest', () async {
      final api = FakePurchasesApi();
      final service = _service(api);
      await service.configure();

      api.reportUpdate(
        customerInfoWith(
          active: [entitlementInfo(productIdentifier: 'plus_annual')],
        ),
      );

      expect(service.latest.entitled, isTrue);
      expect(service.latest.productIdentifier, 'plus_annual');
    });
  });

  group('refresh', () {
    test('asks the store again and reports what it said', () async {
      final api = FakePurchasesApi();
      final service = _service(api);
      await service.configure();
      api.customerInfo = customerInfoWith(active: [entitlementInfo()]);

      final info = await service.refresh();

      expect(info.entitled, isTrue);
      expect(service.latest, info);
    });

    test('a store that does not answer keeps the last known state', () async {
      final api = FakePurchasesApi(
        customerInfo: customerInfoWith(active: [entitlementInfo()]),
      );
      final service = _service(api);
      await service.configure();
      api.customerInfoError = StateError('network down');

      final info = await service.refresh();

      expect(info.entitled, isTrue);
      expect(service.latest.entitled, isTrue);
    });
  });

  group('offerings', () {
    test('maps the current offering onto what the paywall shows', () async {
      final offering = offeringInfo([
        packageInfo(),
        packageInfo(
          identifier: r'$rc_annual',
          packageType: rc.PackageType.annual,
          priceString: '€24.99',
        ),
      ]);
      final api = FakePurchasesApi(
        offeringsResult: rc.Offerings({'default': offering}, current: offering),
      );

      final result = await _service(api).offerings();

      expect(result!.id, 'default');
      expect(result.packages, hasLength(2));
      expect(result.packages.first.period, PlusPeriod.monthly);
      expect(result.packages.last.priceString, '€24.99');
    });

    test('a store without a current offering has nothing to sell', () async {
      expect(await _service(FakePurchasesApi()).offerings(), isNull);
    });

    test('a store error keeps its kind and its message', () async {
      final api = FakePurchasesApi()
        ..offeringsError = storeError(
          rc.PurchasesErrorCode.networkError,
          message: 'The network is down.',
        );
      final service = _service(api);

      final failure = await _failureOf(service.offerings);

      expect(failure.failure, SubscriptionFailure.storeProblem);
      expect(failure.message, 'The network is down.');
    });

    test('anything else is an unknown failure the rider can read', () async {
      final api = FakePurchasesApi()..offeringsError = StateError('boom');
      final service = _service(api);

      final failure = await _failureOf(service.offerings);

      expect(failure.failure, SubscriptionFailure.unknown);
      expect(failure.message, 'The store could not be asked for prices.');
      expect(failure.cause, isStateError);
    });
  });

  group('purchase', () {
    test('a bought package becomes the new customer info', () async {
      final api = FakePurchasesApi()
        ..purchasedInfo = customerInfoWith(active: [entitlementInfo()]);
      final service = _service(api);
      final native = packageInfo();

      final seen = <PlusCustomerInfo>[];
      final subscription = service.customerInfo.listen(seen.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      final info = await service.purchase(fromPackage(native));
      await Future<void>.delayed(Duration.zero);

      expect(info.entitled, isTrue);
      expect(service.latest, info);
      expect(seen.last.entitled, isTrue);
      expect(api.purchases.single.package, same(native));
    });

    test('a package that did not come from the store is never sent', () async {
      final api = FakePurchasesApi();
      final service = _service(api);

      final failure = await _failureOf(
        () => service.purchase(
          const PlusPackage(
            id: r'$rc_monthly',
            title: 'Velorki Plus',
            priceString: '€2.99',
            period: PlusPeriod.monthly,
          ),
        ),
      );

      expect(failure.failure, SubscriptionFailure.unknown);
      expect(failure.message, 'This package did not come from the store.');
      expect(api.purchases, isEmpty);
    });

    test(
      'dismissing the store sheet is a cancellation, not an error',
      () async {
        final api = FakePurchasesApi()
          ..purchaseError = storeError(
            rc.PurchasesErrorCode.purchaseCancelledError,
          );
        final service = _service(api);

        final failure = await _failureOf(
          () => service.purchase(fromPackage(packageInfo())),
        );

        expect(failure.failure, SubscriptionFailure.cancelled);
        expect(failure.message, 'The store reported purchaseCancelledError.');
      },
    );

    test('a device that may not buy anything says so', () async {
      final api = FakePurchasesApi()
        ..purchaseError = storeError(
          rc.PurchasesErrorCode.purchaseNotAllowedError,
        );
      final service = _service(api);

      final failure = await _failureOf(
        () => service.purchase(fromPackage(packageInfo())),
      );

      expect(failure.failure, SubscriptionFailure.notAllowed);
    });

    test('everything the store itself got wrong is a store problem', () async {
      const codes = <rc.PurchasesErrorCode>[
        rc.PurchasesErrorCode.storeProblemError,
        rc.PurchasesErrorCode.networkError,
        rc.PurchasesErrorCode.offlineConnectionError,
        rc.PurchasesErrorCode.productNotAvailableForPurchaseError,
      ];

      for (final code in codes) {
        final api = FakePurchasesApi()..purchaseError = storeError(code);
        final service = _service(api);

        final failure = await _failureOf(
          () => service.purchase(fromPackage(packageInfo())),
        );

        expect(
          failure.failure,
          SubscriptionFailure.storeProblem,
          reason: '${code.name} is the store\'s problem',
        );
      }
    });

    test('an error nobody planned for stays unknown', () async {
      final api = FakePurchasesApi()
        ..purchaseError = storeError(
          rc.PurchasesErrorCode.configurationError,
          message: 'Check your keys.',
        );
      final service = _service(api);

      final failure = await _failureOf(
        () => service.purchase(fromPackage(packageInfo())),
      );

      expect(failure.failure, SubscriptionFailure.unknown);
      expect(failure.message, 'Check your keys.');
    });

    test('a code past the end of the list is the unknown error', () async {
      final api = FakePurchasesApi()
        ..purchaseError = PlatformException(code: '9999');
      final service = _service(api);

      final failure = await _failureOf(
        () => service.purchase(fromPackage(packageInfo())),
      );

      expect(failure.failure, SubscriptionFailure.unknown);
      expect(failure.message, 'The store reported unknownError.');
    });

    test(
      'a code that is not a number at all still reaches the rider',
      () async {
        final api = FakePurchasesApi()
          ..purchaseError = PlatformException(
            code: 'BILLING_UNAVAILABLE',
            message: 'Play Store is not signed in.',
          );
        final service = _service(api);

        final failure = await _failureOf(
          () => service.purchase(fromPackage(packageInfo())),
        );

        expect(failure.failure, SubscriptionFailure.unknown);
        expect(failure.message, 'Play Store is not signed in.');
        expect(failure.cause, isA<PlatformException>());
      },
    );

    test('a nameless error still says something', () async {
      final api = FakePurchasesApi()
        ..purchaseError = PlatformException(code: 'nonsense');
      final service = _service(api);

      final failure = await _failureOf(
        () => service.purchase(fromPackage(packageInfo())),
      );

      expect(failure.message, 'The store reported an error.');
    });
  });

  group('restorePurchases', () {
    test('what the store account owns comes back and is published', () async {
      final api = FakePurchasesApi()
        ..restoredInfo = customerInfoWith(
          active: [entitlementInfo(productIdentifier: 'plus_annual')],
        );
      final service = _service(api);

      final seen = <PlusCustomerInfo>[];
      final subscription = service.customerInfo.listen(seen.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      final info = await service.restorePurchases();
      await Future<void>.delayed(Duration.zero);

      expect(api.restoreCalls, 1);
      expect(info.entitled, isTrue);
      expect(info.productIdentifier, 'plus_annual');
      expect(service.latest, info);
      expect(seen.last, info);
    });

    test('a restore the store refused maps like a purchase does', () async {
      final api = FakePurchasesApi()
        ..restoreError = storeError(rc.PurchasesErrorCode.storeProblemError);
      final service = _service(api);

      final failure = await _failureOf(service.restorePurchases);

      expect(failure.failure, SubscriptionFailure.storeProblem);
    });
  });

  group('dispose', () {
    test('lets the SDK go and stops publishing', () async {
      final api = FakePurchasesApi();
      final service = _service(api);
      await service.configure();
      final listener = api.listeners.single;

      service.dispose();

      expect(api.listeners, isEmpty);
      expect(
        () => listener(customerInfoWith(active: [entitlementInfo()])),
        returnsNormally,
      );
    });

    test('disposing twice is harmless, as a provider teardown may', () async {
      final service = _service(FakePurchasesApi());
      await service.configure();

      service.dispose();

      expect(service.dispose, returnsNormally);
    });
  });
}
