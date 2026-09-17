import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';
import 'package:velorki/features/subscription/presentation/paywall_screen.dart';
import 'package:velorki/features/subscription/presentation/plus_settings_section.dart';
import 'package:velorki/features/subscription/presentation/plus_strings.dart';

import '../../support/app.dart';
import 'support/fake_subscription_service.dart';

Future<List<Uri>> _pump(
  WidgetTester tester,
  Widget child, {
  required FakeSubscriptionService service,
  bool entitled = false,
  List<Override> extraOverrides = const <Override>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final opened = <Uri>[];

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      subscriptionServiceProvider.overrideWithValue(service),
      linkOpenerProvider.overrideWithValue((url) async {
        opened.add(url);
        return true;
      }),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  container.read(plusEntitledProvider.notifier).value = entitled;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return opened;
}

void main() {
  group('PaywallScreen', () {
    testWidgets('lists the four gated features and the legal copy', (
      tester,
    ) async {
      await _pump(
        tester,
        const PaywallScreen(),
        service: FakeSubscriptionService(offering: defaultOffering),
      );

      expect(find.text(l10n.plusFeatureAiAssistant), findsOneWidget);
      expect(find.text(l10n.plusFeatureStrava), findsOneWidget);
      expect(find.text(l10n.plusFeatureRwgps), findsOneWidget);
      expect(find.text(l10n.plusFeatureLinkSharing), findsOneWidget);
      expect(find.textContaining(l10n.plusLegal), findsOneWidget);
      expect(find.text(l10n.settingsTerms), findsOneWidget);
      expect(find.text(l10n.settingsPrivacyPolicy), findsOneWidget);
    });

    testWidgets('shows every package with its price, period and trial', (
      tester,
    ) async {
      await _pump(
        tester,
        const PaywallScreen(),
        service: FakeSubscriptionService(offering: defaultOffering),
      );

      expect(
        find.text(l10n.plusPricePeriod('€2.99', l10n.plusPeriodMonth)),
        findsOneWidget,
      );
      expect(
        find.text(l10n.plusPricePeriod('€24.99', l10n.plusPeriodYear)),
        findsOneWidget,
      );
      expect(find.text(l10n.plusTrialNote(7)), findsOneWidget);
    });

    testWidgets('Subscribe buys the selected package', (tester) async {
      final service = FakeSubscriptionService(offering: defaultOffering);
      await _pump(tester, const PaywallScreen(), service: service);

      await tester.tap(
        find.text(l10n.plusPricePeriod('€24.99', l10n.plusPeriodYear)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.plusSubscribe));
      await tester.pumpAndSettle();

      expect(service.purchases.single.id, plainAnnual.id);
      expect(find.textContaining(l10n.plusPurchaseThanks), findsWidgets);
    });

    testWidgets('a failed purchase is reported, not swallowed', (tester) async {
      final service = FakeSubscriptionService(
        offering: defaultOffering,
        purchaseFailure: const SubscriptionException(
          SubscriptionFailure.storeProblem,
          'billing unavailable',
        ),
      );
      await _pump(tester, const PaywallScreen(), service: service);

      await tester.tap(find.widgetWithText(FilledButton, l10n.plusSubscribe));
      await tester.pumpAndSettle();

      expect(find.textContaining('billing unavailable'), findsOneWidget);
    });

    testWidgets('Restore purchases works without any login', (tester) async {
      final service = FakeSubscriptionService(
        offering: defaultOffering,
        restored: const PlusCustomerInfo(entitled: true),
      );
      await _pump(tester, const PaywallScreen(), service: service);

      await tester.tap(find.text(l10n.plusRestore));
      await tester.pumpAndSettle();

      expect(service.restores, 1);
      expect(find.text(l10n.plusRestored), findsOneWidget);
    });

    testWidgets('a build without a store says so instead of offering nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        const PaywallScreen(),
        service: FakeSubscriptionService(isAvailable: false),
      );

      expect(find.text(l10n.connectionsUnavailable), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, l10n.plusSubscribe),
        findsNothing,
      );
      expect(find.text(l10n.plusRestore), findsNothing);
      // The feature list is still there: a fork's users should know what the
      // official build sells.
      expect(find.text(l10n.plusFeatureAiAssistant), findsOneWidget);
    });

    testWidgets('a store that cannot be reached explains itself', (
      tester,
    ) async {
      await _pump(
        tester,
        const PaywallScreen(),
        service: FakeSubscriptionService(
          offeringsFailure: const SubscriptionException(
            SubscriptionFailure.storeProblem,
            'no connection',
          ),
        ),
      );

      expect(find.textContaining('no connection'), findsOneWidget);
    });

    testWidgets('the terms and privacy links open', (tester) async {
      final opened = await _pump(
        tester,
        const PaywallScreen(),
        service: FakeSubscriptionService(offering: defaultOffering),
      );

      await tester.tap(find.text(l10n.settingsTerms));
      await tester.tap(find.text(l10n.settingsPrivacyPolicy));
      await tester.pumpAndSettle();

      expect(opened.map((u) => u.toString()), [
        velorkiTermsUrl,
        velorkiPrivacyUrl,
      ]);
    });
  });

  group('PlusSettingsSection', () {
    testWidgets('an inactive subscription says so', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: PlusSettingsSection()),
        service: FakeSubscriptionService(),
      );

      expect(find.text(l10n.plusInactive), findsOneWidget);
      expect(find.text(l10n.plusManage), findsNothing);
      expect(find.text(l10n.plusRestore), findsOneWidget);
    });

    testWidgets('an active subscription shows when it renews, and Manage', (
      tester,
    ) async {
      final opened = await _pump(
        tester,
        const Scaffold(body: PlusSettingsSection()),
        entitled: true,
        service: FakeSubscriptionService(
          initial: PlusCustomerInfo(
            entitled: true,
            willRenew: true,
            expiresAt: DateTime(2026, 10, 12),
          ),
        ),
      );

      expect(find.textContaining(l10n.plusActive), findsOneWidget);
      expect(find.textContaining(l10n.plusRenewsOn('').trim()), findsOneWidget);

      await tester.tap(find.text(l10n.plusManage));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(
        opened.single.toString(),
        anyOf(playSubscriptionsUrl, appStoreSubscriptionsUrl),
      );
    });

    testWidgets('the store management URL RevenueCat reported wins', (
      tester,
    ) async {
      final opened = await _pump(
        tester,
        const Scaffold(body: PlusSettingsSection()),
        entitled: true,
        service: FakeSubscriptionService(
          initial: const PlusCustomerInfo(
            entitled: true,
            managementUrl: 'https://example.test/manage',
          ),
        ),
      );

      await tester.tap(find.text(l10n.plusManage));
      await tester.pumpAndSettle();

      expect(opened.single.toString(), 'https://example.test/manage');
    });
  });
}
