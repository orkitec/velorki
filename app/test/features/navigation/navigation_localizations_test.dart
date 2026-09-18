import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/settings/data/language_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the cues follow the app language the rider chose', () {
    final container = ProviderContainer(
      overrides: [appLocaleProvider.overrideWithValue(const Locale('de'))],
    );
    addTearDown(container.dispose);

    expect(container.read(navigationLocalizationsProvider).localeName, 'de');
  });

  test('without a choice the cues follow the platform, English as the '
      'fallback', () {
    final container = ProviderContainer(
      overrides: [appLocaleProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    final l10n = container.read(navigationLocalizationsProvider);
    expect(l10n.localeName, anyOf('en', 'de'));
  });

  test('a language the app has no translation for falls back to English', () {
    final container = ProviderContainer(
      overrides: [appLocaleProvider.overrideWithValue(const Locale('xx'))],
    );
    addTearDown(container.dispose);

    expect(container.read(navigationLocalizationsProvider).localeName, 'en');
  });
}
