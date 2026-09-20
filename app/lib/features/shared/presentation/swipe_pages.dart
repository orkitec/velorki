import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Pages a swipe apart, with dots underneath saying which is up.
///
/// Not a PageView: that needs a height, and a page's height often depends
/// on its content. A horizontal drag is all a swipe needs, and it does not
/// fight a vertical scroll inside a page. With [fill] the pages take all the
/// room they are given, for pages that scroll on their own under a map that
/// stays put.
class SwipePages extends StatelessWidget {
  /// Creates the pages.
  const SwipePages({
    required this.page,
    required this.onPage,
    required this.children,
    this.fill = false,
    super.key,
  });

  /// The page showing.
  final int page;

  /// A swipe asked for another page.
  final ValueChanged<int> onPage;

  /// The pages, in swipe order.
  final List<Widget> children;

  /// Whether the pages fill the space given rather than take their own.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final switcher = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        fit: fill ? StackFit.expand : StackFit.loose,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey<int>(page), child: children[page]),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200 && page < children.length - 1) onPage(page + 1);
        if (velocity > 200 && page > 0) onPage(page - 1);
      },
      child: Column(
        children: [
          if (fill) Expanded(child: switcher) else switcher,
          if (children.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < children.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      width: i == page ? 8 : 6,
                      height: i == page ? 8 : 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == page
                            ? theme.velorki.accent
                            : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
              ],
            ),
            if (fill) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
