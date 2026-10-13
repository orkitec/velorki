import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// What the rider answered the free forecast's dialog.
enum FreeForecastAnswer {
  /// Colour the route from the free forecast, and do not ask again.
  use,

  /// Show what Velorki Plus is.
  seePlus,
}

/// Asks a rider without Velorki Plus, the first time they colour the route
/// by the wind or the rain, whether the free forecast will do: where it
/// comes from and what it lacks, and, where the build offers Plus
/// ([offerPlus]), that Plus has a finer one. `null` when dismissed.
///
/// Scrollable, so a phone turned sideways still reaches every button.
Future<FreeForecastAnswer?> showFreeForecastDialog(
  BuildContext context, {
  required bool offerPlus,
}) => showDialog<FreeForecastAnswer>(
  context: context,
  useRootNavigator: true,
  builder: (context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.weatherFreeForecastTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.weatherFreeForecastBody),
          if (offerPlus) ...[
            const SizedBox(height: 12),
            Text(l10n.weatherFreeForecastPlusBody),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        if (offerPlus)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(FreeForecastAnswer.seePlus),
            child: Text(l10n.weatherFreeForecastSeePlus),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(FreeForecastAnswer.use),
          child: Text(l10n.weatherFreeForecastUse),
        ),
      ],
    );
  },
);
