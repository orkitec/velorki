import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// The in-app explanation shown **before** the system location prompt.
///
/// Both stores expect the reason for a sensitive permission to be visible
/// before the OS dialog, not after. Returns `true` when the user wants to
/// continue to the system prompt.
Future<bool> showLocationRationaleDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.mapLocationRationaleTitle),
        content: Text(l10n.mapLocationRationaleBody),
        actions: <Widget>[
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
