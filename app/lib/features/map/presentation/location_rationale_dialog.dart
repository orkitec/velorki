import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// The in-app explanation shown **before** the system location prompt.
///
/// Both stores expect the reason for a sensitive permission to be visible
/// before the OS dialog, not after. Returns `true` when the user wants to
/// continue to the system prompt.
///
/// On iOS it has one button, Continue, and cannot be dismissed: Apple's
/// guidelines (Privacy) want a screen before the system alert to lead only
/// to the alert, where the rider decides; a way out before it counts as
/// steering the choice. Android keeps "Not now", as Google asks for a way to
/// decline the explanation.
Future<bool> showLocationRationaleDialog(BuildContext context) async {
  final onlyContinue = Theme.of(context).platform == TargetPlatform.iOS;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: !onlyContinue,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.mapLocationRationaleTitle),
        content: Text(l10n.mapLocationRationaleBody),
        actions: <Widget>[
          if (!onlyContinue)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.mapLocationRationaleDeny),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.mapLocationRationaleAllow),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
