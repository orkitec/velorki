import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/search/data/search_preferences_controller.dart';
import 'package:velorki/features/search/domain/search_group.dart';

Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'everything is on, in the declared order, until anyone says otherwise',
    () async {
      final container = await containerWith(const <String, Object>{});

      final preferences = container.read(searchPreferencesProvider);
      expect(preferences.order, SearchGroup.values);
      expect(preferences.disabled, isEmpty);
      expect(preferences.rankOf(SearchGroup.places), 0);
      expect(preferences.rankOf(null), SearchGroup.values.length);
      expect(preferences.isEnabled(null), isTrue);
    },
  );

  test('a reorder and a switch survive a restart', () async {
    final container = await containerWith(const <String, Object>{});
    final controller = container.read(searchPreferencesProvider.notifier);

    await controller.reorder(3, 0);
    await controller.setEnabled(SearchGroup.streets, false);

    expect(
      container.read(searchPreferencesProvider).order.first,
      SearchGroup.cyclingStops,
    );
    expect(container.read(searchPreferencesProvider).disabled, <SearchGroup>{
      SearchGroup.streets,
    });

    // What the next launch reads back out of shared_preferences.
    final prefs = await SharedPreferences.getInstance();
    final restarted = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restarted.dispose);

    final reopened = restarted.read(searchPreferencesProvider);
    expect(reopened.order.first, SearchGroup.cyclingStops);
    expect(reopened.order.toSet(), SearchGroup.values.toSet());
    expect(reopened.disabled, <SearchGroup>{SearchGroup.streets});
    expect(reopened.isEnabled(SearchGroup.streets), isFalse);
  });

  test('switching everything back on leaves nothing behind', () async {
    final container = await containerWith(const <String, Object>{});
    final controller = container.read(searchPreferencesProvider.notifier);

    await controller.setEnabled(SearchGroup.nature, false);
    await controller.setEnabled(SearchGroup.nature, true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('search.groupsDisabled'), isNull);
    expect(container.read(searchPreferencesProvider).disabled, isEmpty);
  });

  test('a stored list this build does not understand is repaired', () async {
    final container = await containerWith(const <String, Object>{
      // A group from a later release, a duplicate, and five groups missing.
      'search.groupOrder': <String>['ferries', 'nature', 'nature', 'transport'],
      'search.groupsDisabled': <String>['ferries', 'services'],
    });

    final preferences = container.read(searchPreferencesProvider);
    expect(preferences.order.first, SearchGroup.nature);
    expect(preferences.order[1], SearchGroup.transport);
    expect(
      preferences.order.length,
      SearchGroup.values.length,
      reason: 'every group the app knows is somewhere in the list',
    );
    expect(preferences.order.toSet(), SearchGroup.values.toSet());
    expect(preferences.disabled, <SearchGroup>{SearchGroup.services});
  });

  test('a drop onto its own place changes nothing', () async {
    final container = await containerWith(const <String, Object>{});
    final controller = container.read(searchPreferencesProvider.notifier);

    await controller.reorder(2, 2);
    await controller.reorder(99, 0);

    expect(container.read(searchPreferencesProvider).order, SearchGroup.values);
  });
}
