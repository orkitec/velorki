import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/units.dart';

/// Settings → Units: metric or imperial, for every distance, speed and height
/// the app shows or speaks.
class UnitsSection extends ConsumerWidget {
  /// Creates the section.
  const UnitsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final system = ref.watch(unitSystemProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsUnits, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          SegmentedButton<UnitSystem>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: UnitSystem.metric,
                label: Text(l10n.unitsMetric),
              ),
              ButtonSegment(
                value: UnitSystem.imperial,
                label: Text(l10n.unitsImperial),
              ),
            ],
            selected: {system},
            onSelectionChanged: (selection) => unawaited(
              ref.read(unitSystemProvider.notifier).select(selection.single),
            ),
          ),
        ],
      ),
    );
  }
}
