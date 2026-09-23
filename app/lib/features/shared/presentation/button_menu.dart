import 'package:flutter/material.dart';

/// An outlined button that opens a popup menu of [entries] under itself.
///
/// A popup menu rather than a `MenuAnchor`: an anchor closes its menu the
/// moment the scroll view it sits in reports any scrolling, and a card that
/// is taller than its sheet reports some on the tap that opened it, so the
/// menu was gone before it could be read. A popup menu is a route of its
/// own and stays until it is chosen from or dismissed.
class ButtonMenu<T> extends StatelessWidget {
  /// Creates the button.
  const ButtonMenu({
    required this.icon,
    required this.label,
    required this.entries,
    required this.onSelected,
    super.key,
  });

  /// The button's icon.
  final IconData icon;

  /// The button's label.
  final String label;

  /// The menu's entries, in order.
  final List<PopupMenuEntry<T>> entries;

  /// Called with the value chosen.
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    onSelected: onSelected,
    position: PopupMenuPosition.under,
    tooltip: label,
    itemBuilder: (context) => entries,
    // The popup takes the tap; the button underneath only looks the part.
    child: IgnorePointer(
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: Icon(icon),
        label: Text(label),
      ),
    ),
  );
}
