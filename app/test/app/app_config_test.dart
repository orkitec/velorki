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
        apiUrl: 'https://api.velorki.com',
        brouterUrl: 'https://api.velorki.com/brouter',
        revenueCatKeyIos: 'appl_xxx',
      );
      expect(config.hasApi, isTrue);
      expect(config.hasBrouter, isTrue);
      expect(config.hasRevenueCat, isTrue);
    });

    test('VELORKI_PLUS_STUB=1 is read, and only that spelling', () {
      // Whether the define is set depends on how this test is run, so the
      // expectation is derived from the same environment.
      const define = String.fromEnvironment('VELORKI_PLUS_STUB');
      expect(AppConfig.fromEnvironment.plusStub, define == '1');
      expect(const AppConfig().plusStub, isFalse);
    });

    test('the Plus stub only counts in a build without a store', () {
      // Unit tests run in debug mode, so the getter sees a non-release build.
      expect(const AppConfig(plusStub: true).stubsPlus, isTrue);
      expect(
        const AppConfig(plusStub: true, revenueCatKeyIos: 'appl_xxx').stubsPlus,
        isFalse,
      );
      expect(
        const AppConfig(
          plusStub: true,
          revenueCatKeyAndroid: 'goog_xxx',
        ).stubsPlus,
        isFalse,
      );
      expect(const AppConfig().stubsPlus, isFalse);
    });

    test('a release build ignores the Plus stub whatever else is set', () {
      expect(
        plusStubActive(stub: true, hasRevenueCat: false, release: false),
        isTrue,
      );
      expect(
        plusStubActive(stub: true, hasRevenueCat: false, release: true),
        isFalse,
      );
      expect(
        plusStubActive(stub: true, hasRevenueCat: true, release: false),
        isFalse,
      );
      expect(
        plusStubActive(stub: false, hasRevenueCat: false, release: false),
        isFalse,
      );
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
