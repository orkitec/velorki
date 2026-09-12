import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';
import 'package:velorki/features/subscription/presentation/paywall_screen.dart';
import 'package:velorki/features/subscription/presentation/plus_settings_section.dart';
import 'package:velorki/features/subscription/presentation/plus_strings.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

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
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
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

      expect(find.text('AI assistant'), findsOneWidget);
      expect(find.text('Strava connection'), findsOneWidget);
      expect(find.text('Ride with GPS connection'), findsOneWidget);
      expect(find.text('Link sharing'), findsOneWidget);
      expect(find.textContaining('renews automatically'), findsOneWidget);
      expect(find.text('Terms of use'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
    });

    testWidgets('shows every package with its price, period and trial', (
      tester,
    ) async {
      await _pump(
        tester,
        const PaywallScreen(),
        service: FakeSubscriptionService(offering: defaultOffering),
      );

      expect(find.text('€2.99 per month'), findsOneWidget);
      expect(find.text('€24.99 per year'), findsOneWidget);
      expect(find.text('Starts with a 7-day free trial.'), findsOneWidget);
    });

    testWidgets('Subscribe buys the selected package', (tester) async {
      final service = FakeSubscriptionService(offering: defaultOffering);
      await _pump(tester, const PaywallScreen(), service: service);

      await tester.tap(find.text('€24.99 per year'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
      await tester.pumpAndSettle();

      expect(service.purchases.single.id, plainAnnual.id);
      expect(find.textContaining('Velorki Plus is active'), findsWidgets);
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

      await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
      await tester.pumpAndSettle();

      expect(find.textContaining('billing unavailable'), findsOneWidget);
    });

    testWidgets('Restore purchases works without any login', (tester) async {
      final service = FakeSubscriptionService(
        offering: defaultOffering,
        restored: const PlusCustomerInfo(entitled: true),
      );
      await _pump(tester, const PaywallScreen(), service: service);

      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();

      expect(service.restores, 1);
      expect(find.text('Your subscription was restored.'), findsOneWidget);
    });

    testWidgets('a build without a store says so instead of offering nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        const PaywallScreen(),
        service: FakeSubscriptionService(isAvailable: false),
      );

      expect(find.text('Not available in this build'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Subscribe'), findsNothing);
      expect(find.text('Restore purchases'), findsNothing);
      // The feature list is still there: a fork's users should know what the
      // official build sells.
      expect(find.text('AI assistant'), findsOneWidget);
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

      await tester.tap(find.text('Terms of use'));
      await tester.tap(find.text('Privacy policy'));
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

      expect(find.text('Not active'), findsOneWidget);
      expect(find.text('Manage'), findsNothing);
      expect(find.text('Restore purchases'), findsOneWidget);
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

      expect(find.textContaining('Active'), findsOneWidget);
      expect(find.textContaining('Renews on'), findsOneWidget);

      await tester.tap(find.text('Manage'));
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

      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();

      expect(opened.single.toString(), 'https://example.test/manage');
    });
  });
}
