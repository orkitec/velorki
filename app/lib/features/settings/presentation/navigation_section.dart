import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/navigation/data/navigation_settings.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Settings → Navigation: the turn directions, whether they are spoken, and
/// whether leaving the route plans a new way back onto it.
class NavigationSection extends ConsumerWidget {
  /// Creates the section.
  const NavigationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(navigationSettingsProvider);
    final controller = ref.read(navigationSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          value: settings.turns,
          title: Text(l10n.settingsTurnDirections),
          subtitle: Text(l10n.settingsTurnDirectionsHint),
          onChanged: (value) => unawaited(controller.setTurns(value)),
        ),
        // The voice only has anything to say while the turns are shown, so it
        // greys out with them; the stored choice is kept either way.
        SwitchListTile(
          value: settings.voice,
          title: Text(l10n.settingsVoiceDirections),
          subtitle: Text(l10n.settingsVoiceDirectionsHint),
          onChanged: settings.turns
              ? (value) => unawaited(controller.setVoice(value))
              : null,
        ),
        // Re-routing needs a route to be matched against, which is what the
        // turn directions do, so it greys out with them too.
        SwitchListTile(
          value: settings.reroute,
          title: Text(l10n.settingsReroute),
          subtitle: Text(l10n.settingsRerouteHint),
          onChanged: settings.turns
              ? (value) => unawaited(controller.setReroute(value))
              : null,
        ),
      ],
    );
  }
}
