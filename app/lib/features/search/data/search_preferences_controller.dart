import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../domain/search_group.dart';

const String _prefsOrder = 'search.groupOrder';
const String _prefsDisabled = 'search.groupsDisabled';

/// Settings → Search, kept in shared_preferences.
///
/// Two string lists of [SearchGroup] names: the order the rider dragged the
/// groups into, and the ones they switched off. Both are read defensively —
/// a name this build does not know is dropped and a group the stored order
/// never mentions is appended in its default place — so a downgrade, or a
/// group added in a later release, cannot leave the search with a list that
/// is missing half of itself.
class SearchPreferencesController extends Notifier<SearchPreferences> {
  @override
  SearchPreferences build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return SearchPreferences(
      order: _readOrder(prefs.getStringList(_prefsOrder)),
      disabled: _readDisabled(prefs.getStringList(_prefsDisabled)),
    );
  }

  /// Moves the group at [oldIndex] so that it sits at [newIndex] afterwards.
  ///
  /// Plain move semantics — take the row out, put it back in at [newIndex] —
  /// which is what a reorderable list view's `onReorderItem` reports.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final order = state.order.toList();
    if (oldIndex < 0 || oldIndex >= order.length) return;
    final target = newIndex.clamp(0, order.length - 1);
    if (target == oldIndex) return;
    order.insert(target, order.removeAt(oldIndex));
    await ref.read(sharedPreferencesProvider).setStringList(
      _prefsOrder,
      <String>[for (final group in order) group.name],
    );
    state = state.copyWith(order: order);
  }

  /// Switches [group] on or off.
  Future<void> setEnabled(SearchGroup group, bool enabled) async {
    final disabled = state.disabled.toSet();
    if (enabled) {
      disabled.remove(group);
    } else {
      disabled.add(group);
    }
    final prefs = ref.read(sharedPreferencesProvider);
    // All on is the default, so it is stored as no key at all.
    if (disabled.isEmpty) {
      await prefs.remove(_prefsDisabled);
    } else {
      await prefs.setStringList(_prefsDisabled, <String>[
        for (final entry in SearchGroup.values)
          if (disabled.contains(entry)) entry.name,
      ]);
    }
    state = state.copyWith(disabled: disabled);
  }

  static List<SearchGroup> _readOrder(List<String>? stored) {
    if (stored == null || stored.isEmpty) return SearchGroup.values;
    final order = <SearchGroup>[];
    for (final name in stored) {
      final group = SearchGroup.byName(name);
      if (group != null && !order.contains(group)) order.add(group);
    }
    for (final group in SearchGroup.values) {
      if (!order.contains(group)) order.add(group);
    }
    return order;
  }

  static Set<SearchGroup> _readDisabled(List<String>? stored) {
    if (stored == null) return const <SearchGroup>{};
    return <SearchGroup>{
      for (final name in stored)
        if (SearchGroup.byName(name) case final SearchGroup group) group,
    };
  }
}

/// Which groups the offline search shows, and in which order.
final searchPreferencesProvider =
    NotifierProvider<SearchPreferencesController, SearchPreferences>(
      SearchPreferencesController.new,
    );
