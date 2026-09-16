import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/search_preferences_controller.dart';
import '../domain/search_group.dart';

/// The Settings row into the search groups.
class SearchSettingsEntry extends StatelessWidget {
  /// Creates the row.
  const SearchSettingsEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.manage_search_outlined),
      title: Text(l10n.searchSettingsTitle),
      subtitle: Text(l10n.searchSettingsCaption),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SearchSettingsScreen()),
      ),
    );
  }
}

/// Settings → Search: the eight groups the offline index answers with, in the
/// order the rider wants them and with the ones they never look for switched
/// off.
///
/// Both the order and the switches take effect on the next keystroke and are
/// written to shared_preferences as they are changed: there is no Save here,
/// and dragging a row is the whole interaction.
class SearchSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SearchSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final preferences = ref.watch(searchPreferencesProvider);
    final controller = ref.read(searchPreferencesProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchSettingsTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              l10n.searchSettingsCaption,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: ReorderableListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 24,
              ),
              // The handle is the only thing that starts a drag: the switch
              // sits in the same row and a long press on it must toggle it,
              // not pick the row up.
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) =>
                  unawaited(controller.reorder(oldIndex, newIndex)),
              children: [
                for (final (index, group) in preferences.order.indexed)
                  _GroupRow(
                    key: ValueKey<String>(group.name),
                    group: group,
                    index: index,
                    enabled: !preferences.disabled.contains(group),
                    onChanged: (value) =>
                        unawaited(controller.setEnabled(group, value)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.index,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final SearchGroup group;
  final int index;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle),
          ),
          const SizedBox(width: 12),
          Icon(searchGroupIcon(group)),
        ],
      ),
      title: Text(searchGroupLabel(l10n, group)),
      trailing: Switch(value: enabled, onChanged: onChanged),
    );
  }
}

/// The localised name of a search group.
String searchGroupLabel(AppLocalizations l10n, SearchGroup group) =>
    switch (group) {
      SearchGroup.places => l10n.searchGroupPlaces,
      SearchGroup.streets => l10n.searchGroupStreets,
      SearchGroup.landmarks => l10n.searchGroupLandmarks,
      SearchGroup.cyclingStops => l10n.searchGroupCyclingStops,
      SearchGroup.overnight => l10n.searchGroupOvernight,
      SearchGroup.nature => l10n.searchGroupNature,
      SearchGroup.transport => l10n.searchGroupTransport,
      SearchGroup.services => l10n.searchGroupServices,
    };

/// The icon a search group wears, the same one its commonest kind wears in a
/// result row.
IconData searchGroupIcon(SearchGroup group) => switch (group) {
  SearchGroup.places => Icons.location_city_outlined,
  SearchGroup.streets => Icons.signpost_outlined,
  SearchGroup.landmarks => Icons.account_balance_outlined,
  SearchGroup.cyclingStops => Icons.pedal_bike_outlined,
  SearchGroup.overnight => Icons.hotel_outlined,
  SearchGroup.nature => Icons.forest_outlined,
  SearchGroup.transport => Icons.train_outlined,
  SearchGroup.services => Icons.local_hospital_outlined,
};
