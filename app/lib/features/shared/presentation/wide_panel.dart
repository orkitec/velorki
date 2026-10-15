import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../../app/shell_layout.dart';
import 'docking_sheet.dart';
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

/// A map tab in a wide window: laid out as on a phone held upright, in a
/// column of [widePanelWidth] on the left, from the window's top down to
/// [widePanelMargin] above the bar (above the window's safe area while the
/// bar is away, for a ride), with the map beside it. Its chrome sits at the
/// column's top and its sheet stands at the bottom as a panel
/// ([PanelSheet]), so every screen keeps the layout it has upright.
///
/// Elsewhere [child] as it is; the same widgets either way, so a window
/// resized across the line keeps the tab's state.
class WidePanelColumn extends StatelessWidget {
  /// Creates the column.
  const WidePanelColumn({required this.child, super.key});

  /// The tab.
  final Widget child;

  /// Whether the tab at [context] is in a wide window's column: its sheet
  /// is then a panel that stands still, as tall as its content.
  static bool panelOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PanelScope>()?.panel ?? false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = ShellLayout.of(context).widePanel;
    // The scaffold counts the bar in the bottom padding while it shows;
    // while it is away the column keeps the margin above the safe area, so
    // the panel's lower corners stand clear of the window's.
    final bottom = math.max(media.padding.bottom, media.viewPadding.bottom);
    final cut = wide ? bottom + widePanelMargin : 0.0;
    final width = widePanelWidth(media.size.width);
    final left = wide ? media.padding.left + widePanelMargin : 0.0;
    final data = !wide
        ? media
        : media.copyWith(
            size: Size(width, media.size.height - cut),
            padding: media.padding.copyWith(left: 0, right: 0, bottom: 0),
            viewPadding: media.viewPadding.copyWith(
              left: 0,
              right: 0,
              bottom: 0,
            ),
            viewInsets: media.viewInsets.copyWith(
              bottom: (media.viewInsets.bottom - cut).clamp(
                0.0,
                double.infinity,
              ),
            ),
          );
    // The tab's navigator clips what it paints to its box: it is given
    // room around the column for the shadows of the panel and the chrome,
    // which each page leaves free again ([WidePanelPage]).
    final room = !wide
        ? EdgeInsets.zero
        : EdgeInsets.only(
            left: math.min(left, widePanelShadowRoom),
            right: widePanelShadowRoom,
            bottom: math.min(cut, widePanelShadowRoom),
          );
    return Padding(
      padding: EdgeInsets.only(
        left: left - room.left,
        bottom: cut - room.bottom,
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: wide ? width + room.horizontal : double.infinity,
          height: double.infinity,
          child: MediaQuery(
            data: data,
            child: _PanelScope(panel: wide, room: room, child: child),
          ),
        ),
      ),
    );
  }
}

/// How far around a wide window's column its panel's and chrome's shadows
/// reach.
const double widePanelShadowRoom = 40;

class _PanelScope extends InheritedWidget {
  const _PanelScope({
    required this.panel,
    required this.room,
    required super.child,
  });

  final bool panel;

  /// The room around the column for its shadows.
  final EdgeInsets room;

  @override
  bool updateShouldNotify(_PanelScope oldWidget) =>
      oldWidget.panel != panel || oldWidget.room != room;
}

/// A map tab's page in its branch's navigator: in a wide window's column,
/// the column itself, inside the room its navigator is given for shadows
/// ([WidePanelColumn]); elsewhere [child] as it is.
class WidePanelPage extends StatelessWidget {
  /// Creates the page's box.
  const WidePanelPage({required this.child, super.key});

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding:
        context.dependOnInheritedWidgetOfExactType<_PanelScope>()?.room ??
        EdgeInsets.zero,
    child: child,
  );
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
