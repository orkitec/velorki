import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/subscription/application/subscription_controller.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';

import 'support/fake_subscription_service.dart';

ProviderContainer _container(FakeSubscriptionService service) {
  final container = ProviderContainer(
    overrides: [subscriptionServiceProvider.overrideWithValue(service)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('revenueCatKeyFor', () {
    const config = AppConfig(
      revenueCatKeyAndroid: 'goog_key',
      revenueCatKeyIos: 'appl_key',
    );

    test('picks the key of the platform it runs on', () {
      expect(revenueCatKeyFor(config, platform: 'android'), 'goog_key');
      expect(revenueCatKeyFor(config, platform: 'ios'), 'appl_key');
      expect(revenueCatKeyFor(config, platform: 'macos'), 'appl_key');
    });

    test('a platform without a key gets none, which is the no-op service', () {
      expect(revenueCatKeyFor(config, platform: 'linux'), isEmpty);
      expect(revenueCatKeyFor(const AppConfig(), platform: 'android'), isEmpty);
    });
  });

  group('NoopSubscriptionService', () {
    test('sells nothing and says so', () async {
      const service = NoopSubscriptionService();
      expect(service.isAvailable, isFalse);
      expect(await service.offerings(), isNull);
      expect(service.latest.entitled, isFalse);
      expect((await service.restorePurchases()).entitled, isFalse);
      await expectLater(
        service.purchase(trialMonthly),
        throwsA(
          isA<SubscriptionException>().having(
            (e) => e.failure,
            'failure',
            SubscriptionFailure.unavailable,
          ),
        ),
      );
    });
  });

  group('startSubscriptions', () {
    test('configures the store and writes the entitlement', () async {
      final service = FakeSubscriptionService(
        initial: const PlusCustomerInfo(entitled: true),
      );
      final container = _container(service);

      startSubscriptions(container);
      await Future<void>.delayed(Duration.zero);

      expect(service.configures, 1);
      expect(container.read(plusEntitledProvider), isTrue);
      expect(
        container.read(plusFeatureProvider(PlusFeature.aiAssistant)),
        isTrue,
      );
    });

    test('a lapsed subscription takes the entitlement away again', () async {
      final service = FakeSubscriptionService(
        initial: const PlusCustomerInfo(entitled: true),
      );
      final container = _container(service);
      startSubscriptions(container);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(plusEntitledProvider), isTrue);

      service.emit(PlusCustomerInfo.none);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(plusEntitledProvider), isFalse);
      expect(
        container.read(plusFeatureProvider(PlusFeature.linkSharing)),
        isFalse,
      );
    });
  });

  group('purchase', () {
    test('a successful purchase entitles the rider', () async {
      final service = FakeSubscriptionService();
      final container = _container(service);

      final info = await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(trialMonthly);

      expect(info?.entitled, isTrue);
      expect(service.purchases.single.id, trialMonthly.id);
      expect(container.read(plusEntitledProvider), isTrue);
      expect(container.read(subscriptionControllerProvider), PlusAction.none);
    });

    test('a cancelled purchase is not an error', () async {
      final service = FakeSubscriptionService(
        purchaseFailure: const SubscriptionException(
          SubscriptionFailure.cancelled,
          'cancelled',
        ),
      );
      final container = _container(service);

      final info = await container
          .read(subscriptionControllerProvider.notifier)
          .purchase(trialMonthly);

      expect(info, isNull);
      expect(container.read(plusEntitledProvider), isFalse);
      expect(container.read(subscriptionControllerProvider), PlusAction.none);
    });

    test('a store failure reaches the caller', () async {
      final service = FakeSubscriptionService(
        purchaseFailure: const SubscriptionException(
          SubscriptionFailure.storeProblem,
          'billing unavailable',
        ),
      );
      final container = _container(service);

      await expectLater(
        container
            .read(subscriptionControllerProvider.notifier)
            .purchase(trialMonthly),
        throwsA(
          isA<SubscriptionException>().having(
            (e) => e.message,
            'message',
            'billing unavailable',
          ),
        ),
      );
      expect(container.read(subscriptionControllerProvider), PlusAction.none);
    });
  });

  group('restore', () {
    test('restoring a subscription entitles without any login', () async {
      final service = FakeSubscriptionService(
        restored: const PlusCustomerInfo(entitled: true),
      );
      final container = _container(service);

      final info = await container
          .read(subscriptionControllerProvider.notifier)
          .restore();

      expect(service.restores, 1);
      expect(info.entitled, isTrue);
      expect(container.read(plusEntitledProvider), isTrue);
    });

    test('restoring nothing leaves the rider where they were', () async {
      final service = FakeSubscriptionService();
      final container = _container(service);

      final info = await container
          .read(subscriptionControllerProvider.notifier)
          .restore();

      expect(info.entitled, isFalse);
      expect(container.read(plusEntitledProvider), isFalse);
    });
  });
}
