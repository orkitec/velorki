import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/presentation/connections_section.dart';
import 'package:velorki/features/integrations/presentation/strava_brand.dart';

import '../../support/app.dart';
import 'support/pump.dart';

const ConnectedAccount _strava = ConnectedAccount(
  service: IntegrationService.strava,
  accessToken: 'access',
  athleteId: '42',
  athleteName: 'Steffen Römer',
);

void main() {
  testWidgets('both connect buttons are enabled', (tester) async {
    await pumpIntegrations(tester, const ConnectionsSection());

    expect(find.text(l10n.serviceStrava), findsOneWidget);
    expect(find.text(l10n.serviceRwgps), findsOneWidget);
    expect(find.text(l10n.connectionsNotConnected), findsNWidgets(2));
    expect(find.text(l10n.connectionsConnectRwgps), findsOneWidget);

    // Strava's official button carries the artwork; the wording lives in its
    // accessibility label, which their guidelines require verbatim.
    final strava = tester.widget<StravaConnectButton>(
      find.byType(StravaConnectButton),
    );
    expect(strava.label, l10n.connectionsConnectStrava);
    expect(strava.onPressed, isNotNull);
  });

  testWidgets('the connect button sits below the title, not beside it', (
    tester,
  ) async {
    // A phone-width screen: with the button in the tile's trailing slot the
    // "Ride with GPS" title wrapped into three lines next to it.
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpIntegrations(tester, const ConnectionsSection());

    final button = find.widgetWithText(
      FilledButton,
      l10n.connectionsConnectRwgps,
    );
    expect(
      find.descendant(of: find.byType(ListTile), matching: button),
      findsNothing,
    );
    final title = tester.getRect(find.text(l10n.serviceRwgps));
    expect(tester.getRect(button).top, greaterThanOrEqualTo(title.bottom));
    // One line of title, not three.
    expect(title.height, lessThan(40));
  });

  testWidgets('both connections are free: without Plus the buttons work '
      'and nothing mentions the subscription', (tester) async {
    await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(entitled: false),
    );

    expect(find.text(l10n.sharePlusLabel), findsNothing);
    expect(find.text(l10n.plusTitle), findsNothing);
    final strava = tester.widget<StravaConnectButton>(
      find.byType(StravaConnectButton),
    );
    expect(strava.onPressed, isNotNull);
    final rwgps = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.connectionsConnectRwgps),
    );
    expect(rwgps.onPressed, isNotNull);
  });

  testWidgets('a build without a relay says so instead of offering a button', (
    tester,
  ) async {
    await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(config: const AppConfig()),
    );

    expect(find.text(l10n.connectionsUnavailable), findsNWidgets(2));
  });

  testWidgets('a connected account shows the athlete and a Disconnect button', (
    tester,
  ) async {
    await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _strava,
        },
      ),
    );

    expect(find.text('Steffen Römer'), findsOneWidget);
    expect(find.text(l10n.connectionsDisconnect), findsOneWidget);
    expect(find.byType(StravaConnectButton), findsNothing);
  });

  testWidgets('connecting stores the account and updates the tile', (
    tester,
  ) async {
    final harness = await pumpIntegrations(tester, const ConnectionsSection());
    harness.connectors[IntegrationService.strava]!.account = _strava;

    await tester.tap(find.byType(StravaConnectButton));
    await tester.pumpAndSettle();
    // What is read and written, before Strava's page opens.
    expect(find.text(l10n.stravaConsentTitle), findsOneWidget);
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();

    expect(harness.connectors[IntegrationService.strava]!.connects, 1);
    expect(find.text('Steffen Römer'), findsOneWidget);
    expect(harness.store.values.keys, contains('integrations.strava.account'));
  });

  testWidgets('a cancelled authorisation says nothing at all', (tester) async {
    final harness = await pumpIntegrations(tester, const ConnectionsSection());
    harness.connectors[IntegrationService.strava]!.failure =
        const IntegrationException.cancelled();

    await tester.tap(find.byType(StravaConnectButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonContinue));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(StravaConnectButton), findsOneWidget);
  });

  testWidgets('a failed authorisation is reported in a snack bar', (
    tester,
  ) async {
    final harness = await pumpIntegrations(tester, const ConnectionsSection());
    harness.connectors[IntegrationService.rwgps]!.failure =
        IntegrationException(
          IntegrationFailure.relayUnavailable,
          (l10n) => l10n.relayBusy,
        );

    await tester.tap(find.text(l10n.connectionsConnectRwgps));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.connectionsConnectFailed(l10n.relayBusy)),
      findsOneWidget,
    );
  });

  testWidgets('disconnecting asks first and then forgets the token', (
    tester,
  ) async {
    final harness = await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _strava,
        },
      ),
    );

    await tester.tap(find.text(l10n.connectionsDisconnect));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.connectionsDisconnectTitle('Strava')),
      findsOneWidget,
    );
    expect(find.text(l10n.connectionsDisconnectStravaBody), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, l10n.connectionsDisconnect),
    );
    await tester.pumpAndSettle();

    expect(harness.connectors[IntegrationService.strava]!.revokes, 1);
    expect(harness.store.values, isEmpty);
    // Strava's terms: a written confirmation that their data is gone.
    expect(find.text(l10n.connectionsDisconnected('Strava')), findsOneWidget);
    expect(find.text(l10n.stravaDataDeleted), findsOneWidget);
    await tester.tap(find.text(l10n.commonOk));
    await tester.pumpAndSettle();
    expect(find.text(l10n.stravaDataDeleted), findsNothing);
    expect(find.byType(StravaConnectButton), findsOneWidget);
  });

  testWidgets('cancelling the disconnect dialog keeps the account', (
    tester,
  ) async {
    final harness = await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _strava,
        },
      ),
    );

    await tester.tap(find.text(l10n.connectionsDisconnect));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(harness.connectors[IntegrationService.strava]!.revokes, 0);
    expect(find.text('Steffen Römer'), findsOneWidget);
  });

  testWidgets('cancelling the consent sheet opens nothing', (tester) async {
    final harness = await pumpIntegrations(tester, const ConnectionsSection());

    await tester.tap(find.byType(StravaConnectButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.stravaConsentReadsTitle), findsOneWidget);
    expect(find.text(l10n.stravaConsentWritesBody), findsOneWidget);
    expect(find.text(l10n.stravaConsentDisconnectBody), findsOneWidget);
    expect(
      find.text(l10n.stravaConsentSupport('ride@velorki.com')),
      findsOneWidget,
    );
    expect(find.text(l10n.settingsPrivacyPolicy), findsOneWidget);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(harness.connectors[IntegrationService.strava]!.connects, 0);
    expect(find.text(l10n.stravaConsentTitle), findsNothing);
  });

  testWidgets('Ride with GPS connects without the Strava consent sheet', (
    tester,
  ) async {
    final harness = await pumpIntegrations(tester, const ConnectionsSection());

    await tester.tap(find.text(l10n.connectionsConnectRwgps));
    await tester.pumpAndSettle();

    expect(find.text(l10n.stravaConsentTitle), findsNothing);
    expect(harness.connectors[IntegrationService.rwgps]!.connects, 1);
  });

  testWidgets('a connected Strava account links to the athlete on Strava', (
    tester,
  ) async {
    final harness = await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(
        accounts: const <IntegrationService, ConnectedAccount>{
          IntegrationService.strava: _strava,
        },
      ),
    );

    await tester.tap(find.text(l10n.rideDetailViewOnStrava));
    await tester.pumpAndSettle();

    expect(harness.openedLinks, [
      Uri.parse('https://www.strava.com/athletes/42'),
    ]);
  });
}
