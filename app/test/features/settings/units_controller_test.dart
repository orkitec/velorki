import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/settings/data/units.dart';

const String _unitsKey = 'units.system';

Future<(ProviderContainer, SharedPreferences)> _container({
  Map<String, Object> initial = const <String, Object>{},
  String? country,
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localeCountryProvider.overrideWithValue(country),
    ],
  );
  addTearDown(container.dispose);
  return (container, prefs);
}

void main() {
  test('a fresh install outside the imperial countries is metric', () async {
    final (container, prefs) = await _container(country: 'DE');

    expect(container.read(unitSystemProvider), UnitSystem.metric);
    // Nothing is written until the rider says something.
    expect(prefs.getString(_unitsKey), isNull);
  });

  test('a phone with no country at all is metric', () async {
    final (container, _) = await _container();

    expect(container.read(unitSystemProvider), UnitSystem.metric);
  });

  test('a fresh install in the United States is imperial', () async {
    final (container, prefs) = await _container(country: 'US');

    expect(container.read(unitSystemProvider), UnitSystem.imperial);
    expect(prefs.getString(_unitsKey), isNull);
  });

  test('Liberia and Myanmar count too, whatever the case', () async {
    for (final country in ['LR', 'MM', 'us']) {
      final (container, _) = await _container(country: country.toUpperCase());
      expect(
        container.read(unitSystemProvider),
        UnitSystem.imperial,
        reason: country,
      );
    }
  });

  test('what was stored is what comes back, country or not', () async {
    final (imperial, _) = await _container(
      initial: <String, Object>{_unitsKey: 'imperial'},
      country: 'DE',
    );
    expect(imperial.read(unitSystemProvider), UnitSystem.imperial);

    // A rider in the States who wants kilometres keeps them.
    final (metric, _) = await _container(
      initial: <String, Object>{_unitsKey: 'metric'},
      country: 'US',
    );
    expect(metric.read(unitSystemProvider), UnitSystem.metric);
  });

  test('an unreadable stored value falls back to the country', () async {
    final (container, _) = await _container(
      initial: <String, Object>{_unitsKey: 'cubits'},
      country: 'US',
    );

    expect(container.read(unitSystemProvider), UnitSystem.imperial);
  });

  test('select persists the choice and rebuilds the listeners', () async {
    final (container, prefs) = await _container(country: 'DE');
    final seen = <UnitSystem>[];
    container.listen(
      unitSystemProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );

    await container
        .read(unitSystemProvider.notifier)
        .select(UnitSystem.imperial);

    expect(prefs.getString(_unitsKey), 'imperial');
    expect(container.read(unitSystemProvider), UnitSystem.imperial);
    expect(seen, [UnitSystem.metric, UnitSystem.imperial]);
  });

  test('picking the default is still written down', () async {
    final (container, prefs) = await _container(country: 'US');

    await container.read(unitSystemProvider.notifier).select(UnitSystem.metric);

    expect(prefs.getString(_unitsKey), 'metric');
  });
}
