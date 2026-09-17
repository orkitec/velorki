import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/settings/data/language_controller.dart';

const String _localeKey = 'language.locale';

Future<(ProviderContainer, SharedPreferences)> _container([
  Map<String, Object> initial = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (container, prefs);
}

void main() {
  test('a fresh install follows the system', () async {
    final (container, _) = await _container();

    expect(container.read(languageSettingProvider), isNull);
    expect(container.read(appLocaleProvider), isNull);
  });

  test('what was stored is what comes back', () async {
    final (container, _) = await _container(<String, Object>{_localeKey: 'de'});

    expect(container.read(appLocaleProvider), const Locale('de'));
  });

  test('a stored tag with a region finds the shipped language', () async {
    final (container, _) = await _container(<String, Object>{
      _localeKey: 'de-AT',
    });

    expect(container.read(appLocaleProvider), const Locale('de'));
  });

  test('a language the app does not ship falls back to the system', () async {
    final (container, _) = await _container(<String, Object>{
      _localeKey: 'fr-FR',
    });

    expect(container.read(appLocaleProvider), isNull);
  });

  test('select persists the choice and rebuilds the listeners', () async {
    final (container, prefs) = await _container();
    final seen = <Locale?>[];
    container.listen(
      appLocaleProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );

    await container
        .read(languageSettingProvider.notifier)
        .select(const Locale('de'));

    expect(prefs.getString(_localeKey), 'de');
    expect(container.read(appLocaleProvider), const Locale('de'));
    expect(seen, [null, const Locale('de')]);
  });

  test('going back to the system clears the key again', () async {
    final (container, prefs) = await _container(<String, Object>{
      _localeKey: 'de',
    });
    final notifier = container.read(languageSettingProvider.notifier);

    await notifier.select(null);

    expect(prefs.containsKey(_localeKey), isFalse);
    expect(container.read(appLocaleProvider), isNull);
  });

  test('supportedLocaleFromTag reads what select writes', () {
    expect(supportedLocaleFromTag(null), isNull);
    expect(supportedLocaleFromTag(''), isNull);
    expect(supportedLocaleFromTag('en'), const Locale('en'));
    expect(supportedLocaleFromTag('de_DE'), const Locale('de'));
    expect(supportedLocaleFromTag('nonsense'), isNull);
  });
}
