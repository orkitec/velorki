import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// What the rider answered the rain radar's dialog.
enum RainRadarAnswer {
  /// Switch the free rain radar on.
  useFree,

  /// Show what Velorki Plus is; the radar stays off.
  seePlus,
}

/// Asks a rider without Velorki Plus, each time they switch the rain radar
/// on, whether the free radar will do: Plus adds measured radar across
/// Europe where the free map has the satellite's estimate. `null` when
/// dismissed. Laid out as the route's free forecast dialog
/// (`showFreeForecastDialog`).
///
/// Scrollable, so a phone turned sideways still reaches every button.
Future<RainRadarAnswer?> showRainRadarDialog(BuildContext context) =>
    showDialog<RainRadarAnswer>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          scrollable: true,
          title: Text(l10n.mapRainRadarPlusTitle),
          content: Text(l10n.mapRainRadarPlusBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(RainRadarAnswer.seePlus),
              child: Text(l10n.mapRainRadarPlusSeePlus),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(RainRadarAnswer.useFree),
              child: Text(l10n.mapRainRadarPlusUseFree),
            ),
          ],
        );
      },
    );
