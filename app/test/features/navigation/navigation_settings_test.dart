import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';

Future<ProviderContainer> _container(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('turn directions and voice are both on out of the box', () async {
    final container = await _container(const <String, Object>{});

    expect(
      container.read(navigationSettingsProvider),
      const NavigationSettings(),
    );
    expect(container.read(navigationSettingsProvider).turns, isTrue);
    expect(container.read(navigationSettingsProvider).voice, isTrue);
  });

  test('stored switches come back', () async {
    final container = await _container(const {
      'navigation.turns': false,
      'navigation.voice': false,
    });

    expect(
      container.read(navigationSettingsProvider),
      const NavigationSettings(turns: false, voice: false),
    );
  });

  test('switching the voice off stores it', () async {
    final container = await _container(const <String, Object>{});

    await container.read(navigationSettingsProvider.notifier).setVoice(false);

    expect(container.read(navigationSettingsProvider).voice, isFalse);
    expect(container.read(navigationSettingsProvider).turns, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('navigation.voice'), isFalse);
  });

  test('switching the turns off stores it', () async {
    final container = await _container(const <String, Object>{});

    await container.read(navigationSettingsProvider.notifier).setTurns(false);

    expect(container.read(navigationSettingsProvider).turns, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('navigation.turns'), isFalse);
  });

  test('switching back on forgets the key rather than storing it', () async {
    final container = await _container(const {'navigation.voice': false});
    expect(container.read(navigationSettingsProvider).voice, isFalse);

    await container.read(navigationSettingsProvider.notifier).setVoice(true);

    expect(container.read(navigationSettingsProvider).voice, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('navigation.voice'), isNull);
  });

  test('a rebuilt container reads what was written', () async {
    final first = await _container(const <String, Object>{});
    await first.read(navigationSettingsProvider.notifier).setTurns(false);

    final prefs = await SharedPreferences.getInstance();
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);

    expect(second.read(navigationSettingsProvider).turns, isFalse);
    expect(second.read(navigationSettingsProvider).voice, isTrue);
  });

  test('copyWith touches only what it is given', () {
    const settings = NavigationSettings();

    expect(
      settings.copyWith(voice: false),
      const NavigationSettings(voice: false),
    );
    expect(settings.copyWith(), settings);
    expect(settings.toString(), 'NavigationSettings(turns: true, voice: true)');
  });
}
