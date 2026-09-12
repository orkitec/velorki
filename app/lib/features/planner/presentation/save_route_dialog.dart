import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Asks for the name a route is saved under.
///
/// Returns the name, or `null` when the user cancelled. The field starts with
/// [initialName] and an empty field falls back to it, so "Save" always works.
Future<String?> showSaveRouteDialog(
  BuildContext context, {
  required String initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SaveRouteDialog(initialName: initialName),
  );
}

class _SaveRouteDialog extends StatefulWidget {
  const _SaveRouteDialog({required this.initialName});

  final String initialName;

  @override
  State<_SaveRouteDialog> createState() => _SaveRouteDialogState();
}

class _SaveRouteDialogState extends State<_SaveRouteDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? widget.initialName : name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.plannerSaveDialogTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: l10n.plannerRouteNameLabel,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.commonSave)),
      ],
    );
  }
}
