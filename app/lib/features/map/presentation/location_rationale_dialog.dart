import 'package:flutter/material.dart';

import 'map_strings.dart';

/// The in-app explanation shown **before** the system location prompt.
///
/// Both stores expect the reason for a sensitive permission to be visible
/// before the OS dialog, not after. Returns `true` when the user wants to
/// continue to the system prompt.
Future<bool> showLocationRationaleDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(MapStrings.locationRationaleTitle),
      content: const Text(MapStrings.locationRationaleBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(MapStrings.locationRationaleDeny),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(MapStrings.locationRationaleAllow),
        ),
      ],
    ),
  );
  return result ?? false;
}
