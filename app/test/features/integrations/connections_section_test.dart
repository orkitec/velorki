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
  testWidgets('an entitled rider sees both connect buttons, enabled', (
    tester,
  ) async {
    await pumpIntegrations(tester, const ConnectionsSection());

    expect(find.text(l10n.serviceStrava), findsOneWidget);
    expect(find.text(l10n.serviceRwgps), findsOneWidget);
    expect(find.text(l10n.connectionsNotConnected), findsNWidgets(2));
    expect(find.text(l10n.connectionsConnectRwgps), findsOneWidget);
    expect(find.text(l10n.connectionsPlusTitle), findsNothing);

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

  testWidgets('without the entitlement the buttons are dead and the Plus '
      'placeholder explains why', (tester) async {
    await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(entitled: false),
    );

    expect(find.text(l10n.connectionsPlusTitle), findsOneWidget);
    expect(find.textContaining(l10n.connectionsPlusBody), findsOneWidget);
    final strava = tester.widget<StravaConnectButton>(
      find.byType(StravaConnectButton),
    );
    expect(strava.onPressed, isNull);
    final rwgps = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.connectionsConnectRwgps),
    );
    expect(rwgps.onPressed, isNull);
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

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(StravaConnectButton), findsOneWidget);
  });

  testWidgets('a failed authorisation is reported in a snack bar', (
    tester,
  ) async {
    final harness = await pumpIntegrations(tester, const ConnectionsSection());
    harness.connectors[IntegrationService.rwgps]!.failure =
        const IntegrationException(
          IntegrationFailure.relayUnavailable,
          'the relay is down',
        );

    await tester.tap(find.text(l10n.connectionsConnectRwgps));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.connectionsConnectFailed('the relay is down')),
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

    await tester.tap(
      find.widgetWithText(FilledButton, l10n.connectionsDisconnect),
    );
    await tester.pumpAndSettle();

    expect(harness.connectors[IntegrationService.strava]!.revokes, 1);
    expect(harness.store.values, isEmpty);
    expect(find.text(l10n.connectionsDisconnected('Strava')), findsOneWidget);
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
}
