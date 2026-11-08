// What `env/fdroid.json` — the configuration the F-Droid build is compiled
// with — means for the interface.
//
// Read from the file rather than written out here, so a key added to it
// later is seen by this test rather than by a rider. See docs/FDROID.md;
// which services the build carries is pinned in
// test/app/proprietary_services_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/subscription/application/offered_plus_features.dart';
import 'package:velorki/features/integrations/application/connections_controller.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/presentation/connections_section.dart';
import 'package:velorki/features/integrations/presentation/import_from_service_menu.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';

import '../features/planner/support/pump.dart';
import '../support/app.dart';
import '../support/settings.dart';

/// `env/fdroid.json`, as `--dart-define-from-file` would hand it to
/// [AppConfig.fromEnvironment].
AppConfig _fdroidConfig() {
  final file = File('env/fdroid.json');
  expect(file.existsSync(), isTrue, reason: 'env/fdroid.json must be tracked');
  final env = (jsonDecode(file.readAsStringSync()) as Map)
      .cast<String, Object?>();
  String read(String key) => (env[key] as String?) ?? '';
  return AppConfig(
    brouterUrl: read('VELORKI_BROUTER_URL'),
    apiUrl: read('VELORKI_API_URL'),
    segmentsUrl: read('VELORKI_SEGMENTS_URL'),
    photonUrl: read('VELORKI_PHOTON_URL'),
    mapStyleUrl: read('VELORKI_MAP_STYLE_URL'),
    mapStyleUrlDark: read('VELORKI_MAP_STYLE_URL_DARK'),
    cyclosmTileUrl: read('VELORKI_CYCLOSM_TILE_URL'),
    revenueCatKeyAndroid: read('VELORKI_REVENUECAT_KEY_ANDROID'),
    revenueCatKeyIos: read('VELORKI_REVENUECAT_KEY_IOS'),
    stravaClientId: read('VELORKI_STRAVA_CLIENT_ID'),
    rwgpsClientId: read('VELORKI_RWGPS_CLIENT_ID'),
    oauthScheme: read('VELORKI_OAUTH_SCHEME'),
    storeUrlAndroid: read('VELORKI_STORE_URL_ANDROID'),
    storeUrlIos: read('VELORKI_STORE_URL_IOS'),
    googleWebClientId: read('VELORKI_GOOGLE_WEB_CLIENT_ID'),
    cloudKitTokenDevelopment: read('VELORKI_CLOUDKIT_TOKEN_DEVELOPMENT'),
    cloudKitTokenProduction: read('VELORKI_CLOUDKIT_TOKEN_PRODUCTION'),
  );
}

Override _config() => appConfigProvider.overrideWithValue(_fdroidConfig());

/// The flavour's other half: `main_fdroid.dart` takes the Plus offer away.
Override _noPlus() => plusOfferedProvider.overrideWithValue(false);

/// The F-Droid build's overrides together, as its entry point installs them.
List<Override> _fdroid() => [_config(), _noPlus()];

void main() {
  test('env/fdroid.json carries no store, no Google account and neither '
      'partner service', () {
    final config = _fdroidConfig();
    expect(config.stravaClientId, isEmpty);
    expect(config.rwgpsClientId, isEmpty);
    expect(config.revenueCatKeyAndroid, isEmpty);
    expect(config.revenueCatKeyIos, isEmpty);
    expect(config.googleWebClientId, isEmpty);
    expect(config.cloudKitTokenProduction, isEmpty);
    // What it does carry: the map, the search and the tile mirror, which is
    // the whole point of the flavour.
    expect(config.mapStyleUrl, isNotEmpty);
    expect(config.segmentsUrl, isNotEmpty);
    expect(config.photonUrl, isNotEmpty);
  });

  test('so neither partner service counts as configured', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        _config(),
      ],
    );
    addTearDown(container.dispose);
    for (final service in IntegrationService.values) {
      expect(
        container.read(integrationConfiguredProvider(service)),
        isFalse,
        reason: '$service',
      );
      expect(container.read(integrationConnectorProvider(service)), isNull);
    }
  });

  testWidgets('Settings offers no Connections row', (tester) async {
    await pumpApp(
      tester,
      initialLocation: settingsRoute,
      extraOverrides: [_config()],
    );
    await tester.pumpAndSettle();

    expect(settingsRow(SettingsTopic.connections), findsNothing);
    expect(find.text(l10n.settingsConnections), findsNothing);
    // The rest of Settings is untouched.
    expect(settingsRow(SettingsTopic.plus), findsOneWidget);
    expect(settingsRow(SettingsTopic.mapsData), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('and the page itself, reached by its link, offers nothing', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: settingsConnectionsRoute,
      extraOverrides: [_config()],
    );
    await tester.pumpAndSettle();

    expect(find.byType(ConnectionTile), findsNothing);
    expect(find.text(l10n.serviceStrava), findsNothing);
    expect(find.text(l10n.serviceRwgps), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('the Library has no "import from a service" action', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: libraryRoute,
      extraOverrides: [_config()],
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImportFromServiceButton), findsOneWidget);
    expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);
    await unmountApp(tester);
  });

  test('with Plus taken away, nothing is offered and so nothing is an entry '
      'point', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        ..._fdroid(),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(offeredPlusFeaturesProvider), isEmpty);
    for (final feature in PlusFeature.values) {
      expect(
        container.read(plusFeatureOfferedProvider(feature)),
        isFalse,
        reason: '$feature',
      );
    }
  });

  test('and the ordinary build offers all three, as it always has', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        appConfigProvider.overrideWithValue(
          const AppConfig(apiUrl: 'https://api.velorki.test'),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(offeredPlusFeaturesProvider),
      PlusFeature.values,
      reason: 'the default must stay what every other build gets',
    );
  });

  testWidgets('Settings offers neither Velorki Plus nor the AI assistant', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: settingsRoute,
      extraOverrides: _fdroid(),
    );
    await tester.pumpAndSettle();

    expect(settingsRow(SettingsTopic.plus), findsNothing);
    expect(settingsRow(SettingsTopic.assistant), findsNothing);
    expect(find.text(l10n.plusTitle), findsNothing);
    // Nothing left in "Sync & Plus", so no caption over an empty group.
    expect(settingsRow(SettingsTopic.sync), findsNothing);
    expect(settingsRow(SettingsTopic.connections), findsNothing);
    expect(find.text(l10n.settingsGroupSyncPlus.toUpperCase()), findsNothing);
    expect(find.text(l10n.settingsGroupRiding.toUpperCase()), findsOneWidget);
    // What a rider can still do is all there.
    expect(settingsRow(SettingsTopic.mapsData), findsOneWidget);
    expect(settingsRow(SettingsTopic.appearance), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('and the ordinary build keeps both rows', (tester) async {
    await pumpApp(
      tester,
      initialLocation: settingsRoute,
      extraOverrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(apiUrl: 'https://api.velorki.test'),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(settingsRow(SettingsTopic.plus), findsOneWidget);
    expect(settingsRow(SettingsTopic.assistant), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the planner has no Ask button', (tester) async {
    await pumpApp(
      tester,
      initialLocation: plannerRoute,
      extraOverrides: _fdroid(),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.assistantAction), findsNothing);
    // The free actions beside it are untouched.
    expect(find.text(l10n.loopAction), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('and the ordinary build keeps it where there is a relay', (
    tester,
  ) async {
    await pumpApp(
      tester,
      initialLocation: plannerRoute,
      extraOverrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(apiUrl: 'https://api.velorki.test'),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.assistantAction), findsOneWidget);
    await unmountApp(tester);
  });

  test(
    'the weather map keeps only the free sources — no relay radar',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          ..._fdroid(),
        ],
      );
      addTearDown(container.dispose);
      // The OPERA and DPC composites are drawn by the relay for Plus riders;
      // without Plus granted they are never composed in, so the map falls back
      // to the free sources the phone fetches itself, which is the whole point
      // of the free weather map.
      final sources = container.read(weatherMapSourcesProvider);
      expect(sources, isNotEmpty);
      expect(
        sources.map((s) => s.id),
        isNot(contains(anyOf(contains('opera'), contains('dpc')))),
      );
      // And the route forecast, which is relay-only, is not offered either.
      expect(
        container.read(plusFeatureOfferedProvider(PlusFeature.weather)),
        isFalse,
      );
    },
  );
}
