import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki/features/integrations/presentation/connections_section.dart';

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

    expect(find.text('Strava'), findsOneWidget);
    expect(find.text('Ride with GPS'), findsOneWidget);
    expect(find.text('Not connected'), findsNWidgets(2));
    // Strava's brand guidelines require this wording verbatim.
    expect(find.text('Connect with Strava'), findsOneWidget);
    expect(find.text('Connect with Ride with GPS'), findsOneWidget);
    expect(find.text('Velorki Plus'), findsNothing);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Connect with Strava'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('without the entitlement the buttons are dead and the Plus '
      'placeholder explains why', (tester) async {
    await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(entitled: false),
    );

    expect(find.text('Velorki Plus'), findsOneWidget);
    expect(find.textContaining('part of Velorki Plus'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Connect with Strava'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a build without a relay says so instead of offering a button', (
    tester,
  ) async {
    await pumpIntegrations(
      tester,
      const ConnectionsSection(),
      harness: IntegrationsHarness(config: const AppConfig()),
    );

    expect(find.text('Not available in this build'), findsNWidgets(2));
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
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Connect with Strava'), findsNothing);
  });

  testWidgets('connecting stores the account and updates the tile', (
    tester,
  ) async {
    final harness = await pumpIntegrations(tester, const ConnectionsSection());
    harness.connectors[IntegrationService.strava]!.account = _strava;

    await tester.tap(find.text('Connect with Strava'));
    await tester.pumpAndSettle();

    expect(harness.connectors[IntegrationService.strava]!.connects, 1);
    expect(find.text('Steffen Römer'), findsOneWidget);
    expect(harness.store.values.keys, contains('integrations.strava.account'));
  });

  testWidgets('a cancelled authorisation says nothing at all', (tester) async {
    final harness = await pumpIntegrations(tester, const ConnectionsSection());
    harness.connectors[IntegrationService.strava]!.failure =
        const IntegrationException.cancelled();

    await tester.tap(find.text('Connect with Strava'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Connect with Strava'), findsOneWidget);
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

    await tester.tap(find.text('Connect with Ride with GPS'));
    await tester.pumpAndSettle();

    expect(find.text('Could not connect: the relay is down'), findsOneWidget);
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

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect Strava?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();

    expect(harness.connectors[IntegrationService.strava]!.revokes, 1);
    expect(harness.store.values, isEmpty);
    expect(find.text('Strava disconnected'), findsOneWidget);
    expect(find.text('Connect with Strava'), findsOneWidget);
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

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(harness.connectors[IntegrationService.strava]!.revokes, 0);
    expect(find.text('Steffen Römer'), findsOneWidget);
  });
}
