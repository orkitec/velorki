import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/live_figure_preferences.dart';
import '../domain/live_figures.dart';
import 'live_figures_view.dart';

/// Opens the ride figures list on the root navigator, over the bar and any
/// sheet: from Settings and from the live sheet alike.
Future<void> openLiveFiguresSettings(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const LiveFiguresSettingsScreen(),
      ),
    );

/// The Settings row into the ride figures.
class LiveFiguresSettingsEntry extends StatelessWidget {
  /// Creates the row.
  const LiveFiguresSettingsEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.dashboard_customize_outlined),
      title: Text(l10n.liveFiguresTitle),
      subtitle: Text(l10n.liveFiguresCaption),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(openLiveFiguresSettings(context)),
    );
  }
}

/// Settings → Ride figures: every figure a ride can show, in the order the
/// rider wants them and with the ones they never read switched off.
///
/// The grid on the sheet takes the figures in this order, the bar the sheet
/// folds into the first four, the glance view the first two; a figure with
/// nothing to show just then — a sensor not connected, no route followed —
/// gives its place to the next. Written as it is changed, as the search
/// groups are: no Save, and dragging a row is the whole interaction.
class LiveFiguresSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const LiveFiguresSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final preferences = ref.watch(liveFigurePreferencesProvider);
    final controller = ref.read(liveFigurePreferencesProvider.notifier);
    final onCount = preferences.shown.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.liveFiguresTitle),
        actions: [
          // An icon, so the title keeps its room in every language.
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: l10n.liveFiguresReset,
            onPressed: preferences.isDefault
                ? null
                : () => unawaited(controller.reset()),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              l10n.liveFiguresCaption,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: ReorderableListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 24,
              ),
              // The handle is the only thing that starts a drag: a long
              // press on the switch in the same row must toggle it.
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) =>
                  unawaited(controller.reorder(oldIndex, newIndex)),
              children: [
                for (final (index, figure) in preferences.order.indexed)
                  _FigureRow(
                    key: ValueKey<String>(figure.name),
                    figure: figure,
                    index: index,
                    enabled: !preferences.disabled.contains(figure),
                    // The last one on stays on: a ride with no figures
                    // would be a sheet of nothing.
                    locked:
                        onCount == 1 && !preferences.disabled.contains(figure),
                    onChanged: (value) =>
                        unawaited(controller.setEnabled(figure, value)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.figure,
    required this.index,
    required this.enabled,
    required this.locked,
    required this.onChanged,
    super.key,
  });

  final LiveFigure figure;
  final int index;
  final bool enabled;
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(liveFigureLabel(figure, l10n)),
      trailing: Switch(value: enabled, onChanged: locked ? null : onChanged),
    );
  }
}
