import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../../app/shell_layout.dart';
import 'floating_bar.dart';

/// The air between a wide window's edge and the panel, and between the
/// panel and the bar under it.
const double widePanelMargin = 16;

/// The width of the bar's glass in a wide window, centred at the bottom:
/// about a large phone's, so the four tabs keep their spacing.
const double wideBarWidth = 480;

/// How wide the panel on the left of a wide window [windowWidth] wide is:
/// about a phone held upright, never narrower than the narrowest (an iPhone
/// SE), so each tab's sheet keeps the content it was made for, and the rest
/// is map.
double widePanelWidth(double windowWidth) =>
    (windowWidth * 0.38).clamp(375.0, 420.0);

/// Where the panel ends on the right of a wide window described by
/// [screen] (the window's own metrics): the visible map starts there.
double widePanelRight(MediaQueryData screen) =>
    screen.padding.left + widePanelMargin + widePanelWidth(screen.size.width);

/// What the bar takes from the bottom of a wide window described by
/// [screen]: the safe area, the air under the bar and the bar.
double wideBarCover(MediaQueryData screen) =>
    screen.viewPadding.bottom +
    floatingBarBottomGapFor(screen, defaultTargetPlatform) +
    floatingBarHeight;

/// Where a tab's sheet rests in a wide window, as a share of its panel's
/// [length]: a panel beside the map is not in the map's way, so it rests
/// tall, its top a little under the tab's search and chips.
double widePanelResting(double length) =>
    length <= 0 ? 0.6 : ((length - 220) / length).clamp(0.42, 0.75);

/// A map tab in a wide window: laid out as on a phone held upright, in a
/// column of [widePanelWidth] on the left, from the window's top down to the
/// bar (to the bottom while the bar is away, for a ride or the keyboard),
/// with the map beside it. Its chrome sits at the column's top and its sheet
/// rises in it as a panel, so every screen keeps the layout it has upright.
///
/// Elsewhere [child] as it is; the same widgets either way, so a window
/// resized across the line keeps the tab's state.
class WidePanelColumn extends StatelessWidget {
  /// Creates the column.
  const WidePanelColumn({required this.child, super.key});

  /// The tab.
  final Widget child;

  /// Whether the tab at [context] is in a wide window's column that ends
  /// above the bar: its sheet's lower edge is then in view, with nothing to
  /// dock into. While the bar is away (a ride, the keyboard) the column
  /// reaches the window's bottom and the sheet is the phone's again,
  /// docking into the ride's figures bar.
  static bool aboveBarOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AboveBarScope>()?.aboveBar ??
      false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = ShellLayout.of(context).widePanel;
    // The scaffold counts the bar in the bottom padding while it shows.
    final barShown = media.padding.bottom > media.viewPadding.bottom + 1;
    final cut = wide && barShown ? media.padding.bottom + widePanelMargin : 0.0;
    final width = widePanelWidth(media.size.width);
    final left = wide ? media.padding.left + widePanelMargin : 0.0;
    final data = !wide
        ? media
        : media.copyWith(
            size: Size(width, media.size.height - cut),
            padding: media.padding.copyWith(
              left: 0,
              right: 0,
              bottom: barShown ? 0 : null,
            ),
            viewPadding: media.viewPadding.copyWith(
              left: 0,
              right: 0,
              bottom: barShown ? 0 : null,
            ),
            viewInsets: media.viewInsets.copyWith(
              bottom: (media.viewInsets.bottom - cut).clamp(
                0.0,
                double.infinity,
              ),
            ),
          );
    return Padding(
      padding: EdgeInsets.only(left: left, bottom: cut),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: wide ? width : double.infinity,
          height: double.infinity,
          child: MediaQuery(
            data: data,
            child: _AboveBarScope(aboveBar: wide && barShown, child: child),
          ),
        ),
      ),
    );
  }
}

class _AboveBarScope extends InheritedWidget {
  const _AboveBarScope({required this.aboveBar, required super.child});

  final bool aboveBar;

  @override
  bool updateShouldNotify(_AboveBarScope oldWidget) =>
      oldWidget.aboveBar != aboveBar;
}

/// A page that is not a map (the settings, a page pushed over the shell) in
/// a wide window: a column of readable width in the middle, the page's
/// colour either side. Elsewhere [child] as it is, filling what it gets.
///
/// The same widgets either way, so a window resized across the line keeps
/// the page's state; and nothing here takes a touch.
class WideReadingColumn extends StatelessWidget {
  /// Creates the column.
  const WideReadingColumn({required this.child, super.key});

  /// The page.
  final Widget child;

  /// The widest a page's content gets.
  static const double maxWidth = 720;

  @override
  Widget build(BuildContext context) {
    final wide = ShellLayout.of(context).widePanel;
    return CustomPaint(
      painter: _Backdrop(
        wide ? Theme.of(context).scaffoldBackgroundColor : null,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: wide ? maxWidth : double.infinity,
          height: double.infinity,
          child: child,
        ),
      ),
    );
  }
}

/// The page's colour beside a [WideReadingColumn], painted only: a coloured
/// box would take every touch.
class _Backdrop extends CustomPainter {
  const _Backdrop(this.color);

  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final color = this.color;
    if (color != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_Backdrop oldDelegate) => oldDelegate.color != color;
}

/// The platform's own page transition with the page in a
/// [WideReadingColumn]: every page pushed as a [MaterialPageRoute] (the
/// settings' pages, the offline data, the ride figures) reads at a readable
/// width in a wide window, and is as it always was elsewhere. The router's
/// own pages are wrapped where they are built.
class WidePageTransitionsBuilder extends PageTransitionsBuilder {
  /// Wraps [inner].
  const WidePageTransitionsBuilder(this.inner);

  /// The platform's transition.
  final PageTransitionsBuilder inner;

  /// The platforms' default transitions, each wrapped.
  static Map<TargetPlatform, PageTransitionsBuilder> get all => {
    for (final MapEntry(:key, :value)
        in const PageTransitionsTheme().builders.entries)
      key: WidePageTransitionsBuilder(value),
  };

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      inner.delegatedTransition;

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    WideReadingColumn(child: child),
  );

  @override
  bool operator ==(Object other) =>
      other is WidePageTransitionsBuilder && other.inner == inner;

  @override
  int get hashCode => inner.hashCode;
}
