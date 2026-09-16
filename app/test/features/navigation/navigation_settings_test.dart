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
  test('turns, voice and re-routing are all on out of the box', () async {
    final container = await _container(const <String, Object>{});

    expect(
      container.read(navigationSettingsProvider),
      const NavigationSettings(),
    );
    expect(container.read(navigationSettingsProvider).turns, isTrue);
    expect(container.read(navigationSettingsProvider).voice, isTrue);
    expect(container.read(navigationSettingsProvider).reroute, isTrue);
  });

  test('stored switches come back', () async {
    final container = await _container(const {
      'navigation.turns': false,
      'navigation.voice': false,
      'navigation.reroute': false,
    });

    expect(
      container.read(navigationSettingsProvider),
      const NavigationSettings(turns: false, voice: false, reroute: false),
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

  test('switching re-routing off stores it', () async {
    final container = await _container(const <String, Object>{});

    await container.read(navigationSettingsProvider.notifier).setReroute(false);

    expect(container.read(navigationSettingsProvider).reroute, isFalse);
    expect(container.read(navigationSettingsProvider).turns, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('navigation.reroute'), isFalse);
  });

  test('switching re-routing back on forgets the key', () async {
    final container = await _container(const {'navigation.reroute': false});
    expect(container.read(navigationSettingsProvider).reroute, isFalse);

    await container.read(navigationSettingsProvider.notifier).setReroute(true);

    expect(container.read(navigationSettingsProvider).reroute, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('navigation.reroute'), isNull);
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
    expect(second.read(navigationSettingsProvider).reroute, isTrue);
  });

  test('copyWith touches only what it is given', () {
    const settings = NavigationSettings();

    expect(
      settings.copyWith(voice: false),
      const NavigationSettings(voice: false),
    );
    expect(
      settings.copyWith(reroute: false),
      const NavigationSettings(reroute: false),
    );
    expect(settings.copyWith(), settings);
    expect(
      settings.toString(),
      'NavigationSettings(turns: true, voice: true, reroute: true, '
      'leadSeconds: 10, voiceId: null)',
    );
  });

  test('the lead is ten seconds out of the box', () async {
    final container = await _container(const <String, Object>{});

    expect(container.read(navigationSettingsProvider).leadSeconds, 10);
  });

  test('a stored lead comes back', () async {
    final container = await _container(const {'navigation.leadSeconds': 20});

    expect(container.read(navigationSettingsProvider).leadSeconds, 20);
  });

  test('setting the lead stores it', () async {
    final container = await _container(const <String, Object>{});

    await container
        .read(navigationSettingsProvider.notifier)
        .setLeadSeconds(15);

    expect(container.read(navigationSettingsProvider).leadSeconds, 15);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('navigation.leadSeconds'), 15);
  });

  test('setting the lead back to ten forgets the key', () async {
    final container = await _container(const {'navigation.leadSeconds': 20});

    await container
        .read(navigationSettingsProvider.notifier)
        .setLeadSeconds(10);

    expect(container.read(navigationSettingsProvider).leadSeconds, 10);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('navigation.leadSeconds'), isFalse);
  });

  test('the lead stays between 5 and 30 seconds', () async {
    final container = await _container(const {'navigation.leadSeconds': 1});
    expect(container.read(navigationSettingsProvider).leadSeconds, 5);

    await container
        .read(navigationSettingsProvider.notifier)
        .setLeadSeconds(99);

    expect(container.read(navigationSettingsProvider).leadSeconds, 30);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('navigation.leadSeconds'), 30);
  });

  test('the voice is the system default out of the box', () async {
    final container = await _container(const <String, Object>{});

    expect(container.read(navigationSettingsProvider).voiceId, isNull);
  });

  test('a stored voice comes back', () async {
    final container = await _container(const {'navigation.voiceId': 'v1'});

    expect(container.read(navigationSettingsProvider).voiceId, 'v1');
  });

  test('choosing a voice stores it, and the default forgets the key', () async {
    final container = await _container(const <String, Object>{});
    final controller = container.read(navigationSettingsProvider.notifier);

    await controller.setVoiceId('v2');
    expect(container.read(navigationSettingsProvider).voiceId, 'v2');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('navigation.voiceId'), 'v2');

    await controller.setVoiceId(null);
    expect(container.read(navigationSettingsProvider).voiceId, isNull);
    expect(prefs.containsKey('navigation.voiceId'), isFalse);
  });
}
