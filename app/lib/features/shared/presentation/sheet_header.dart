import 'package:flutter/material.dart';

/// The height of a card's toolbar row, under the handle strip.
const double sheetHeaderDp = 48;

/// The pinned first row of a card over the map: a back arrow or nothing,
/// the title, and the actions at the right. It stays put while the list
/// scrolls under it, and it is part of the scrollable, so a drag on it
/// moves the card the way a drag on the handle does.
///
/// It reaches up under the handle strip the sheet draws over it, painting
/// the sheet's surface there, so the list never shows through the strip.
class SliverSheetHeader extends StatelessWidget {
  /// Creates the header.
  const SliverSheetHeader({
    required this.title,
    this.leading,
    this.actions = const <Widget>[],
    super.key,
  });

  /// The row's title; one line, cut with an ellipsis.
  final String title;

  /// What sits before the title: a back arrow on a detail, nothing on a
  /// list.
  final Widget? leading;

  /// The buttons at the right.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SliverPersistentHeader(
    pinned: true,
    delegate: _SheetHeaderDelegate(
      title: title,
      leading: leading,
      actions: actions,
    ),
  );
}

class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SheetHeaderDelegate({
    required this.title,
    required this.leading,
    required this.actions,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  double get minExtent => sheetHeaderDp;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(leading == null ? 20 : 4, 0, 8, 0),
        child: SizedBox(
          height: sheetHeaderDp,
          child: Row(
            children: [
              ?leading,
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SheetHeaderDelegate old) =>
      old.title != title || old.leading != leading || old.actions != actions;
}
