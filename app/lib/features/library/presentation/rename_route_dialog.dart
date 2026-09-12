import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Asks for a new name for a saved route. Returns `null` when cancelled.
Future<String?> showRenameRouteDialog(
  BuildContext context, {
  required String initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _RenameRouteDialog(initialName: initialName),
  );
}

class _RenameRouteDialog extends StatefulWidget {
  const _RenameRouteDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameRouteDialog> createState() => _RenameRouteDialogState();
}

class _RenameRouteDialogState extends State<_RenameRouteDialog> {
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
    if (name.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.libraryRenameTitle),
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
