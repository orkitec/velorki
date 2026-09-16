import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/navigation_settings.dart';

/// Which of the switches to show.
enum NavigationToggle {
  /// All three.
  all,

  /// Turn directions and voice only.
  turnsAndVoice,

  /// Re-routing only.
  reroute,
}

/// The navigation switches — turn directions, voice, re-routing — as they
/// appear in Settings, for any screen that wants them.
///
/// The record sheet shows the same rows below "Keep screen on", so a rider
/// mid-ride can silence the voice without leaving the ride; both places
/// read and write the one stored setting.
class NavigationToggles extends ConsumerWidget {
  /// Creates the switches. [contentPadding] matches the rows around them.
  const NavigationToggles({
    super.key,
    this.contentPadding,
    this.only = NavigationToggle.all,
  });

  /// Padding for each row; `null` keeps the list tile default.
  final EdgeInsetsGeometry? contentPadding;

  /// Which rows to show; Settings splits them around the voice's own rows.
  final NavigationToggle only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(navigationSettingsProvider);
    final controller = ref.read(navigationSettingsProvider.notifier);
    final showTurns = only != NavigationToggle.reroute;
    final showReroute = only != NavigationToggle.turnsAndVoice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTurns)
          SwitchListTile(
            contentPadding: contentPadding,
            value: settings.turns,
            title: Text(l10n.settingsTurnDirections),
            subtitle: Text(l10n.settingsTurnDirectionsHint),
            onChanged: (value) => unawaited(controller.setTurns(value)),
          ),
        // The voice only has anything to say while the turns are shown, so it
        // greys out with them; the stored choice is kept either way.
        if (showTurns)
          SwitchListTile(
            contentPadding: contentPadding,
            value: settings.voice,
            title: Text(l10n.settingsVoiceDirections),
            subtitle: Text(l10n.settingsVoiceDirectionsHint),
            onChanged: settings.turns
                ? (value) => unawaited(controller.setVoice(value))
                : null,
          ),
        // Re-routing needs a route to be matched against, which is what the
        // turn directions do, so it greys out with them too.
        if (showReroute)
          SwitchListTile(
            contentPadding: contentPadding,
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
