import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// A dialog with one text field, for a route's description or its link.
///
/// Save hands the trimmed text back, an empty one included, which is how
/// the field is cleared; Cancel hands back `null`.
Future<String?> showEditTextDialog(
  BuildContext context, {
  required String title,
  required String? initial,
  String? hint,
  int maxLines = 1,
  TextInputType? keyboardType,
}) => showDialog<String>(
  context: context,
  builder: (context) => _EditTextDialog(
    title: title,
    initial: initial ?? '',
    hint: hint,
    maxLines: maxLines,
    keyboardType: keyboardType,
  ),
);

class _EditTextDialog extends StatefulWidget {
  const _EditTextDialog({
    required this.title,
    required this.initial,
    required this.maxLines,
    this.hint,
    this.keyboardType,
  });

  final String title;
  final String initial;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<_EditTextDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.maxLines > 1
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
