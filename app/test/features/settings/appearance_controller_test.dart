import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';

const String _modeKey = 'appearance.mode';
const String _accentKey = 'appearance.accent';
const String _mapKey = 'appearance.map';
const String _overlayDarkKey = 'appearance.overlay_dark';

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
  test('a fresh install follows the system and rides on volt', () async {
    final (container, _) = await _container();

    final appearance = container.read(appearanceSettingProvider);

    expect(appearance.mode, ThemeMode.system);
    expect(appearance.accent, AccentPreset.volt);
    expect(appearance, const Appearance());
  });

  test('what was stored is what comes back', () async {
    final (container, _) = await _container(<String, Object>{
      _modeKey: 'dark',
      _accentKey: 'berry',
    });

    expect(container.read(appearanceSettingProvider).mode, ThemeMode.dark);
    expect(
      container.read(appearanceSettingProvider).accent,
      AccentPreset.berry,
    );
  });

  test('an unreadable stored value falls back to the defaults', () async {
    final (container, _) = await _container(<String, Object>{
      _modeKey: 'sepia',
      _accentKey: 'chartreuse',
    });

    expect(container.read(appearanceSettingProvider).mode, ThemeMode.system);
    expect(container.read(appearanceSettingProvider).accent, AccentPreset.volt);
  });

  test('setMode persists the choice and rebuilds the listeners', () async {
    final (container, prefs) = await _container();
    final seen = <ThemeMode>[];
    container.listen(
      appearanceSettingProvider,
      (_, next) => seen.add(next.mode),
      fireImmediately: true,
    );

    await container
        .read(appearanceSettingProvider.notifier)
        .setMode(ThemeMode.dark);

    expect(prefs.getString(_modeKey), 'dark');
    expect(container.read(appearanceSettingProvider).mode, ThemeMode.dark);
    // The accent is left alone.
    expect(container.read(appearanceSettingProvider).accent, AccentPreset.volt);
    expect(seen, [ThemeMode.system, ThemeMode.dark]);
  });

  test('setAccent persists the choice and rebuilds the listeners', () async {
    final (container, prefs) = await _container();
    final seen = <AccentPreset>[];
    container.listen(
      appearanceSettingProvider,
      (_, next) => seen.add(next.accent),
      fireImmediately: true,
    );

    await container
        .read(appearanceSettingProvider.notifier)
        .setAccent(AccentPreset.ember);

    expect(prefs.getString(_accentKey), 'ember');
    expect(
      container.read(appearanceSettingProvider).accent,
      AccentPreset.ember,
    );
    expect(container.read(appearanceSettingProvider).mode, ThemeMode.system);
    expect(seen, [AccentPreset.volt, AccentPreset.ember]);
  });

  test('going back to the defaults clears the keys again', () async {
    final (container, prefs) = await _container(<String, Object>{
      _modeKey: 'light',
      _accentKey: 'glacier',
    });
    final notifier = container.read(appearanceSettingProvider.notifier);

    await notifier.setMode(ThemeMode.system);
    await notifier.setAccent(AccentPreset.volt);

    expect(prefs.containsKey(_modeKey), isFalse);
    expect(prefs.containsKey(_accentKey), isFalse);
    expect(container.read(appearanceSettingProvider), const Appearance());
  });

  test('both choices survive together', () async {
    final (container, prefs) = await _container();
    final notifier = container.read(appearanceSettingProvider.notifier);

    await notifier.setMode(ThemeMode.light);
    await notifier.setAccent(AccentPreset.glacier);

    expect(prefs.getString(_modeKey), 'light');
    expect(prefs.getString(_accentKey), 'glacier');
    expect(
      container.read(appearanceSettingProvider),
      const Appearance(mode: ThemeMode.light, accent: AccentPreset.glacier),
    );
  });

  test('setMapLook persists the choice and auto clears the key', () async {
    final (container, prefs) = await _container();
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.auto);

    await container
        .read(appearanceSettingProvider.notifier)
        .setMapLook(MapLook.night);
    expect(prefs.getString(_mapKey), 'night');
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.night);

    await container
        .read(appearanceSettingProvider.notifier)
        .setMapLook(MapLook.auto);
    expect(prefs.containsKey(_mapKey), isFalse);
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.auto);
  });

  test('an unknown stored map look falls back to auto', () async {
    final (container, _) = await _container(<String, Object>{_mapKey: 'sepia'});
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.auto);
  });

  test('the cycling overlay is inverted on dark maps to begin with', () async {
    final (container, _) = await _container();

    expect(
      container.read(appearanceSettingProvider).overlayDark,
      OverlayDarkMode.inverted,
    );
  });

  test('setOverlayDark persists the choice and inverted clears it', () async {
    final (container, prefs) = await _container();
    final notifier = container.read(appearanceSettingProvider.notifier);

    await notifier.setOverlayDark(OverlayDarkMode.dimmed);
    expect(prefs.getString(_overlayDarkKey), 'dimmed');
    expect(
      container.read(appearanceSettingProvider).overlayDark,
      OverlayDarkMode.dimmed,
    );
    // The map look is left alone.
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.auto);

    await notifier.setOverlayDark(OverlayDarkMode.inverted);
    expect(prefs.containsKey(_overlayDarkKey), isFalse);
    expect(container.read(appearanceSettingProvider), const Appearance());
  });

  test('what was stored for the overlay comes back', () async {
    final (container, _) = await _container(<String, Object>{
      _overlayDarkKey: 'unchanged',
    });

    expect(
      container.read(appearanceSettingProvider).overlayDark,
      OverlayDarkMode.unchanged,
    );
  });

  test('an unknown stored overlay mode falls back to inverted', () async {
    final (container, _) = await _container(<String, Object>{
      _overlayDarkKey: 'solarised',
    });

    expect(
      container.read(appearanceSettingProvider).overlayDark,
      OverlayDarkMode.inverted,
    );
  });
}
