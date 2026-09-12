import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';

Future<ProviderContainer> _container([
  Map<String, Object> initialPrefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer.test(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig', () {
    test('defaults to a fully local build when nothing is defined', () {
      const config = AppConfig.fromEnvironment;
      expect(config.apiUrl, isEmpty);
      expect(config.hasApi, isFalse);
      expect(config.hasBrouter, isFalse);
      expect(config.hasRevenueCat, isFalse);
      expect(config.oauthScheme, 'velorki');
    });

    test('feature flags follow the configured URLs and keys', () {
      const config = AppConfig(
        apiUrl: 'https://api.velorki.app',
        brouterUrl: 'https://api.velorki.app/brouter',
        revenueCatKeyIos: 'appl_xxx',
      );
      expect(config.hasApi, isTrue);
      expect(config.hasBrouter, isTrue);
      expect(config.hasRevenueCat, isTrue);
    });
  });

  group('effectiveConfigProvider', () {
    test('returns the build-time config when nothing is overridden', () async {
      final container = await _container();
      expect(
        container.read(effectiveConfigProvider),
        container.read(appConfigProvider),
      );
    });

    test('overlays stored overrides', () async {
      final container = await _container({
        'server_override.brouter_url': 'http://10.0.2.2:17777',
      });
      final config = container.read(effectiveConfigProvider);
      expect(config.brouterUrl, 'http://10.0.2.2:17777');
      expect(config.hasBrouter, isTrue);
      expect(config.photonUrl, container.read(appConfigProvider).photonUrl);
    });

    test('setting and resetting an override updates the config', () async {
      final container = await _container();
      final notifier = container.read(serverOverridesProvider.notifier);

      await notifier.setApiUrl('  https://relay.example  ');
      expect(
        container.read(effectiveConfigProvider).apiUrl,
        'https://relay.example',
      );
      expect(container.read(effectiveConfigProvider).hasApi, isTrue);

      await notifier.reset();
      expect(container.read(serverOverridesProvider).isEmpty, isTrue);
      expect(container.read(effectiveConfigProvider).apiUrl, isEmpty);
    });

    test('an empty value clears the stored override', () async {
      final container = await _container({
        'server_override.photon_url': 'https://photon.example',
      });
      await container.read(serverOverridesProvider.notifier).setPhotonUrl('');
      expect(container.read(serverOverridesProvider).photonUrl, isEmpty);
    });
  });
}
