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

  /// What leaving the route does, only.
  reroute,
}

/// The navigation switches — turn directions, voice — and the choice of what
/// leaving the route does, as they
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
        // Leaving the route only means something while the turns are
        // matched against it, so the choice greys out with them.
        if (showReroute) ...[
          ListTile(
            contentPadding: contentPadding,
            enabled: settings.turns,
            title: Text(l10n.settingsRerouteMode),
          ),
          RadioGroup<RerouteMode>(
            groupValue: settings.rerouteMode,
            onChanged: (mode) {
              if (mode != null && settings.turns) {
                unawaited(controller.setRerouteMode(mode));
              }
            },
            child: Column(
              children: [
                for (final mode in RerouteMode.values)
                  RadioListTile<RerouteMode>(
                    contentPadding: contentPadding,
                    value: mode,
                    enabled: settings.turns,
                    title: Text(rerouteModeLabel(mode, l10n)),
                    subtitle: Text(rerouteModeHint(mode, l10n)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The name of [mode] in the choice.
String rerouteModeLabel(RerouteMode mode, AppLocalizations l10n) =>
    switch (mode) {
      RerouteMode.guideBack => l10n.settingsRerouteGuideBack,
      RerouteMode.newRoute => l10n.settingsRerouteNewRoute,
      RerouteMode.off => l10n.settingsRerouteOff,
    };

/// The line under [mode]'s name.
String rerouteModeHint(RerouteMode mode, AppLocalizations l10n) =>
    switch (mode) {
      RerouteMode.guideBack => l10n.settingsRerouteGuideBackHint,
      RerouteMode.newRoute => l10n.settingsRerouteNewRouteHint,
      RerouteMode.off => l10n.settingsRerouteOffHint,
    };
