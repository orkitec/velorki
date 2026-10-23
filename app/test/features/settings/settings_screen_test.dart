import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki/app/platform_features.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/integrations/presentation/connections_section.dart';
import 'package:velorki/features/sensors/data/health_gateway.dart';
import 'package:velorki/features/sensors/testing/fake_health_gateway.dart';
import 'package:velorki/features/settings/presentation/language_section.dart';
import 'package:velorki/features/settings/presentation/rider_section.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';
import 'package:velorki/features/sync/application/cloud_sync_controller.dart';
import 'package:velorki/features/sync/domain/sync_service.dart';

import '../../support/app.dart';
import '../../support/settings.dart';
import '../planner/support/pump.dart';

void main() {
  testWidgets('the overview has every row in its group, Sync first', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: settingsRoute,
      extraOverrides: [
        offeredSyncServicesProvider.overrideWithValue([SyncService.icloud]),
        healthGatewayProvider.overrideWithValue(FakeHealthGateway()),
      ],
    );
    await tester.pumpAndSettle();

    double top(Finder finder) => tester.getTopLeft(finder).dy;
    final order = [
      find.text(l10n.settingsGroupSyncPlus.toUpperCase()),
      settingsRow(SettingsTopic.sync),
      settingsRow(SettingsTopic.plus),
      settingsRow(SettingsTopic.connections),
      find.text(l10n.settingsGroupRiding.toUpperCase()),
      settingsRow(SettingsTopic.navigation),
      settingsRow(SettingsTopic.recording),
      settingsRow(SettingsTopic.rider),
      settingsRow(SettingsTopic.sensors),
      find.text(l10n.settingsGroupApp.toUpperCase()),
      settingsRow(SettingsTopic.appearance),
      settingsRow(SettingsTopic.assistant),
      settingsRow(SettingsTopic.mapsData),
      settingsRow(SettingsTopic.about),
    ];
    for (final finder in order) {
      expect(finder, findsOneWidget);
    }
    for (var i = 1; i < order.length; i++) {
      expect(top(order[i]), greaterThan(top(order[i - 1])), reason: '$i');
    }
    // The state each row can tell cheaply.
    expect(
      find.descendant(
        of: settingsRow(SettingsTopic.sync),
        matching: find.text(l10n.cloudSyncServiceOff),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: settingsRow(SettingsTopic.plus),
        matching: find.text(l10n.plusInactive),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: settingsRow(SettingsTopic.connections),
        matching: find.text(l10n.connectionsNotConnected),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: settingsRow(SettingsTopic.appearance),
        matching: find.text(
          '${l10n.appearanceModeSystem} · ${l10n.unitsMetric} · '
          '${languageName(Locale(l10n.localeName))}',
        ),
      ),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('a row opens its page, and Back comes back to the overview', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: settingsRoute);
    await tester.pumpAndSettle();

    await openSettingsTopic(tester, SettingsTopic.rider);
    expect(find.byType(RiderSection), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(l10n.settingsRiderAndBike),
      ),
      findsOneWidget,
    );
    await tapBack(tester);
    expect(find.byType(RiderSection), findsNothing);
    expect(settingsRow(SettingsTopic.rider), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a row whose section has nothing to offer is not there', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: settingsRoute,
      extraOverrides: [
        platformFeaturesProvider.overrideWithValue(
          const PlatformFeatures(recording: false, accountConnections: false),
        ),
      ],
    );
    await tester.pumpAndSettle();

    // No cloud to sync with and no health store in the test.
    for (final gone in [
      SettingsTopic.sync,
      SettingsTopic.connections,
      SettingsTopic.navigation,
      SettingsTopic.recording,
      SettingsTopic.sensors,
    ]) {
      expect(settingsRow(gone), findsNothing, reason: '$gone');
    }
    for (final kept in [
      SettingsTopic.plus,
      SettingsTopic.rider,
      SettingsTopic.appearance,
      SettingsTopic.assistant,
      SettingsTopic.mapsData,
      SettingsTopic.about,
    ]) {
      expect(settingsRow(kept), findsOneWidget, reason: '$kept');
    }
    await unmountApp(tester);
  });

  testWidgets('Settings → Connections has a location of its own', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: settingsRoute);
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(SettingsScreen)))
        .go(settingsConnectionsRoute);
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionsSection), findsOneWidget);
    await tapBack(tester);
    expect(find.byType(ConnectionsSection), findsNothing);
    expect(settingsRow(SettingsTopic.connections), findsOneWidget);
    await unmountApp(tester);
  });
}
