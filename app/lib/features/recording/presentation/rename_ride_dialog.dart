import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Asks for a new name for a recorded ride. Returns `null` when cancelled.
Future<String?> showRenameRideDialog(
  BuildContext context, {
  required String initialName,
}) => showDialog<String>(
  context: context,
  builder: (context) => _RenameRideDialog(initialName: initialName),
);

class _RenameRideDialog extends StatefulWidget {
  const _RenameRideDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameRideDialog> createState() => _RenameRideDialogState();
}

class _RenameRideDialogState extends State<_RenameRideDialog> {
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
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.rideDetailRenameTitle),
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
