import 'package:flutter/material.dart';

/// Below this much height for the dialog, in logical pixels, it changes to
/// its compact form.
const double textEntryDialogCompactHeight = 260;

/// A dialog that asks for text: an [AlertDialog] of [title], [content] and
/// [actions] where there is room for one.
///
/// A phone turned sideways with the keyboard up leaves about a hundred
/// pixels of height, less than an [AlertDialog] needs even scrollable, since
/// it keeps its buttons out of the scroll. There the dialog sits closer to
/// the edges and scrolls title, field and buttons as one, the field first in
/// view, so nothing overflows and every button can be reached.
class TextEntryDialog extends StatelessWidget {
  /// Creates the dialog.
  const TextEntryDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });

  /// The dialog's title.
  final Widget title;

  /// The field, and whatever goes with it.
  final Widget content;

  /// The buttons, the confirming one last.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final room = media.size.height - media.viewInsets.vertical;
    if (room >= textEntryDialogCompactHeight) {
      return AlertDialog(title: title, content: content, actions: actions);
    }
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefaultTextStyle(style: theme.textTheme.titleMedium!, child: title),
            const SizedBox(height: 4),
            content,
            const SizedBox(height: 4),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
