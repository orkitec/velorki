import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';

void main() {
  group('PlusIntroOffer', () {
    test('a trial length in days is what the paywall promises', () {
      const day = PlusIntroOffer(
        priceString: '€0.00',
        periodUnit: 'day',
        periodCount: 7,
        isFree: true,
      );

      expect(day.days, 7);
      expect(
        const PlusIntroOffer(
          priceString: '€0.00',
          periodUnit: 'week',
          periodCount: 2,
          isFree: true,
        ).days,
        14,
      );
      expect(
        const PlusIntroOffer(
          priceString: '€0.00',
          periodUnit: 'month',
          periodCount: 1,
          isFree: true,
        ).days,
        30,
      );
      expect(
        const PlusIntroOffer(
          priceString: '€0.00',
          periodUnit: 'year',
          periodCount: 1,
          isFree: true,
        ).days,
        365,
      );
    });

    test('a unit nobody knows has no length rather than a wrong one', () {
      const offer = PlusIntroOffer(
        priceString: '€0.00',
        periodUnit: 'fortnight',
        periodCount: 1,
        isFree: true,
      );

      expect(offer.days, isNull);
    });

    test('two identical offers are the same offer', () {
      const one = PlusIntroOffer(
        priceString: '€0.00',
        periodUnit: 'day',
        periodCount: 7,
        isFree: true,
      );
      const same = PlusIntroOffer(
        priceString: '€0.00',
        periodUnit: 'day',
        periodCount: 7,
        isFree: true,
      );
      const cheaper = PlusIntroOffer(
        priceString: '€0.99',
        periodUnit: 'day',
        periodCount: 7,
        isFree: false,
      );

      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(one, isNot(cheaper));
      expect(one, isNot(Object()));
    });

    test('reads as its price and length in the log', () {
      const offer = PlusIntroOffer(
        priceString: '€0.00',
        periodUnit: 'day',
        periodCount: 7,
        isFree: true,
      );

      expect(offer.toString(), 'PlusIntroOffer(€0.00, 7 day)');
    });
  });

  group('PlusPackage', () {
    test('a free introductory phase is a free trial', () {
      const package = PlusPackage(
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

      expect(package.hasFreeTrial, isTrue);
    });

    test('a discounted first period is not a free trial', () {
      const package = PlusPackage(
        id: r'$rc_monthly',
        title: 'Velorki Plus',
        priceString: '€2.99',
        period: PlusPeriod.monthly,
        introOffer: PlusIntroOffer(
          priceString: '€0.99',
          periodUnit: 'month',
          periodCount: 1,
          isFree: false,
        ),
      );

      expect(package.hasFreeTrial, isFalse);
    });

    test('no introductory phase at all is no trial', () {
      const package = PlusPackage(
        id: r'$rc_annual',
        title: 'Velorki Plus',
        priceString: '€24.99',
        period: PlusPeriod.annual,
      );

      expect(package.hasFreeTrial, isFalse);
      expect(package.native, isNull);
      expect(package.toString(), r'PlusPackage($rc_annual, €24.99, annual)');
    });
  });

  group('PlusCustomerInfo', () {
    test('nobody has bought anything until they have', () {
      expect(PlusCustomerInfo.none.entitled, isFalse);
      expect(PlusCustomerInfo.none.expiresAt, isNull);
      expect(PlusCustomerInfo.none.willRenew, isFalse);
      expect(PlusCustomerInfo.none.managementUrl, isNull);
      expect(PlusCustomerInfo.none.productIdentifier, isNull);
    });

    test('two infos saying the same thing are equal', () {
      final expiry = DateTime.utc(2026, 3, 1);
      final one = PlusCustomerInfo(
        entitled: true,
        expiresAt: expiry,
        willRenew: true,
        managementUrl: 'https://example.test/manage',
        productIdentifier: 'plus_annual',
      );
      final same = PlusCustomerInfo(
        entitled: true,
        expiresAt: expiry,
        willRenew: true,
        managementUrl: 'https://example.test/manage',
        productIdentifier: 'plus_annual',
      );

      expect(one, same);
      expect(one.hashCode, same.hashCode);
    });

    test('every field it carries can tell two infos apart', () {
      final base = PlusCustomerInfo(
        entitled: true,
        expiresAt: DateTime.utc(2026, 3, 1),
        willRenew: true,
        managementUrl: 'https://example.test/manage',
        productIdentifier: 'plus_annual',
      );
      final others = <PlusCustomerInfo>[
        PlusCustomerInfo(
          entitled: false,
          expiresAt: base.expiresAt,
          willRenew: true,
          managementUrl: base.managementUrl,
          productIdentifier: base.productIdentifier,
        ),
        PlusCustomerInfo(
          entitled: true,
          expiresAt: DateTime.utc(2027, 3, 1),
          willRenew: true,
          managementUrl: base.managementUrl,
          productIdentifier: base.productIdentifier,
        ),
        PlusCustomerInfo(
          entitled: true,
          expiresAt: base.expiresAt,
          managementUrl: base.managementUrl,
          productIdentifier: base.productIdentifier,
        ),
        PlusCustomerInfo(
          entitled: true,
          expiresAt: base.expiresAt,
          willRenew: true,
          productIdentifier: base.productIdentifier,
        ),
        PlusCustomerInfo(
          entitled: true,
          expiresAt: base.expiresAt,
          willRenew: true,
          managementUrl: base.managementUrl,
          productIdentifier: 'plus_monthly',
        ),
      ];

      for (final other in others) {
        expect(base, isNot(other), reason: '$other should differ from $base');
      }
      expect(base, isNot(Object()));
    });

    test('the log only needs the entitlement and when it ends', () {
      final info = PlusCustomerInfo(
        entitled: true,
        expiresAt: DateTime.utc(2026, 3, 1),
      );

      expect(
        info.toString(),
        'PlusCustomerInfo(entitled: true, expiresAt: ${info.expiresAt})',
      );
      expect(
        PlusCustomerInfo.none.toString(),
        'PlusCustomerInfo(entitled: false, expiresAt: null)',
      );
    });
  });

  group('PlusOffering', () {
    test('reads as its name and how much it has on offer', () {
      const offering = PlusOffering(
        id: 'default',
        packages: <PlusPackage>[
          PlusPackage(
            id: r'$rc_monthly',
            title: 'Velorki Plus',
            priceString: '€2.99',
            period: PlusPeriod.monthly,
          ),
        ],
      );

      expect(offering.toString(), 'PlusOffering(default, 1 packages)');
    });
  });

  group('SubscriptionException', () {
    test('says what failed and why, for the log', () {
      const failure = SubscriptionException(
        SubscriptionFailure.cancelled,
        'The store sheet was dismissed.',
      );

      expect(
        failure.toString(),
        'SubscriptionException(cancelled: The store sheet was dismissed.)',
      );
      expect(failure.cause, isNull);
    });
  });
}
