import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../recording/data/recording_settings.dart';
import '../../recording/domain/gps_precision.dart';

/// Settings → Recording: how hard the GPS is driven, and the one switch that
/// trades everything else for battery.
class RecordingSection extends ConsumerWidget {
  /// Creates the section.
  const RecordingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(recordingSettingsProvider);
    final controller = ref.read(recordingSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.settingsGpsPrecision,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              SegmentedButton<GpsPrecision>(
                showSelectedIcon: false,
                segments: [
                  for (final precision in GpsPrecision.values)
                    ButtonSegment(
                      value: precision,
                      label: Text(gpsPrecisionLabel(l10n, precision)),
                    ),
                ],
                selected: {settings.precision},
                onSelectionChanged: (selection) =>
                    unawaited(controller.setPrecision(selection.single)),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.settingsGpsPrecisionHint,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: settings.saver,
          title: Text(l10n.settingsBatterySaver),
          subtitle: Text(l10n.settingsBatterySaverHint),
          onChanged: (value) => unawaited(controller.setSaver(value)),
        ),
      ],
    );
  }
}

/// The localised name of a GPS precision profile.
String gpsPrecisionLabel(AppLocalizations l10n, GpsPrecision precision) =>
    switch (precision) {
      GpsPrecision.saver => l10n.gpsPrecisionSaver,
      GpsPrecision.normal => l10n.gpsPrecisionNormal,
      GpsPrecision.precise => l10n.gpsPrecisionPrecise,
    };
