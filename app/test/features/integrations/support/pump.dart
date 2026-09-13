import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/integrations/application/connections_controller.dart';
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/data/integration_connector.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/integrations/common/data/secure_key_value_store.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/settings/data/package_info_provider.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_api/velorki_api.dart';

/// A build with a relay and both client ids, so the integrations exist.
const AppConfig configuredBuild = AppConfig(
  apiUrl: 'https://relay.test',
  stravaClientId: '1234',
  rwgpsClientId: 'abcd',
);

/// A connector whose answers the test sets.
class FakeConnector implements IntegrationConnector {
  /// Creates a connector for [service].
  FakeConnector(this.service, {this.account, this.failure});

  @override
  final IntegrationService service;

  /// What [connect] answers.
  ConnectedAccount? account;

  /// Thrown by [connect] when set.
  Object? failure;

  /// How often [connect] ran.
  int connects = 0;

  /// How often [revoke] ran.
  int revokes = 0;

  @override
  Future<ConnectedAccount> connect() async {
    connects++;
    if (failure != null) throw failure!;
    return account ?? ConnectedAccount(service: service, accessToken: 'token');
  }

  @override
  Future<void> revoke(ConnectedAccount account) async => revokes++;
}

/// Everything an integrations widget test needs.
class IntegrationsHarness {
  /// Creates a harness.
  IntegrationsHarness({
    this.entitled = true,
    this.config = configuredBuild,
    Map<IntegrationService, ConnectedAccount>? accounts,
  }) : store = InMemorySecureKeyValueStore(<String, String>{
         if (accounts != null)
           for (final entry in accounts.entries)
             ConnectedAccountsRepository.keyFor(entry.key): entry.value
                 .encode(),
       });

  /// Whether the Plus entitlement is held.
  final bool entitled;

  /// The build-time configuration.
  final AppConfig config;

  /// The stand-in for the platform keychain.
  final InMemorySecureKeyValueStore store;

  /// The connectors the controller runs.
  final Map<IntegrationService, FakeConnector> connectors =
      <IntegrationService, FakeConnector>{
        for (final service in IntegrationService.values)
          service: FakeConnector(service),
      };

  /// Every URL the UI tried to open.
  final List<Uri> openedLinks = <Uri>[];

  /// The overrides to hand to a [ProviderScope].
  List<Override> overrides(SharedPreferences prefs) => <Override>[
    sharedPreferencesProvider.overrideWithValue(prefs),
    appConfigProvider.overrideWithValue(config),
    secureKeyValueStoreProvider.overrideWithValue(store),
    integrationConnectorProvider.overrideWith(
      (ref, service) => connectors[service],
    ),
    linkOpenerProvider.overrideWithValue((url) async {
      openedLinks.add(url);
      return true;
    }),
  ];
}

/// A container with the integrations' platform edges replaced, and nothing
/// else.
///
/// Everything above those edges — the dio clients, the connectors, the token
/// sources, the loaders — is the app's own wiring, so a test can read a
/// provider and assert what this build really produces.
///
/// [accounts] seeds the stand-in keychain; [relay] stands in for the relay
/// client, which otherwise talks HTTP; [packageInfo] for the plugin that reads
/// the app version; [deepLinks] for the links the platform delivers. Each is
/// only overridden when it is given, so a test of the provider that builds one
/// of them simply leaves it out.
Future<ProviderContainer> integrationsContainer({
  AppConfig config = configuredBuild,
  Map<IntegrationService, ConnectedAccount> accounts =
      const <IntegrationService, ConnectedAccount>{},
  RelayClient? relay,
  PackageInfo? packageInfo,
  Stream<Uri>? deepLinks,
  InMemorySecureKeyValueStore? store,
  Map<String, Object> initialPrefs = const <String, Object>{},
  List<Override> extraOverrides = const <Override>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{...initialPrefs});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      appConfigProvider.overrideWithValue(config),
      secureKeyValueStoreProvider.overrideWithValue(
        store ??
            InMemorySecureKeyValueStore(<String, String>{
              for (final entry in accounts.entries)
                ConnectedAccountsRepository.keyFor(entry.key): entry.value
                    .encode(),
            }),
      ),
      if (relay != null) relayClientProvider.overrideWithValue(relay),
      if (packageInfo != null)
        packageInfoProvider.overrideWith((ref) => packageInfo),
      if (deepLinks != null)
        incomingDeepLinksProvider.overrideWith((ref) => deepLinks),
      ...extraOverrides,
    ],
  );
  // Disposing twice is a no-op, so a test may still dispose it by hand to
  // watch what the providers release.
  addTearDown(container.dispose);
  return container;
}

/// Pumps [child] with the integrations fakes in place.
Future<IntegrationsHarness> pumpIntegrations(
  WidgetTester tester,
  Widget child, {
  IntegrationsHarness? harness,
  List<Override> extraOverrides = const <Override>[],
  Size surfaceSize = const Size(1000, 2000),
}) async {
  final h = harness ?? IntegrationsHarness();
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [...h.overrides(prefs), ...extraOverrides],
  );
  addTearDown(container.dispose);
  container.read(plusEntitledProvider.notifier).value = h.entitled;

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
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}
