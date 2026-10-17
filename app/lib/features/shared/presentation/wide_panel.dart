import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../app/shell_layout.dart';
import '../../../app/tab_fade.dart';

/// The air between a wide window's edge (its safe area) and the column.
const double widePanelMargin = 16;

/// How wide the column of a wide window [windowWidth] wide is: about a
/// phone held upright, never narrower than an iPhone SE, so every screen
/// keeps the layout it was made for, and the rest is map. Where that would
/// leave the map too little ([wideColumnCompact]: an iPad upright, a
/// foldable's inner screen upright) the column is the narrowest phone's,
/// [wideCompactColumnWidth], with the compact top.
double widePanelWidth(double windowWidth) => wideColumnCompact(windowWidth)
    ? wideCompactColumnWidth
    : _regularColumnWidth(windowWidth);

double _regularColumnWidth(double windowWidth) =>
    (windowWidth * 0.38).clamp(375.0, 420.0);

/// The width of a compact column: the narrowest phone's, which the app is
/// laid out for already (an iPad's Slide Over window is as narrow).
const double wideCompactColumnWidth = 320;

/// The least share of a wide window's width the map beside a regular
/// column is to have; with less the column is compact.
const double wideMinMapShare = 0.55;

/// Whether the column of a wide window [windowWidth] wide is compact: a
/// regular column and its margin would leave the map less than
/// [wideMinMapShare] of the width.
bool wideColumnCompact(double windowWidth) =>
    windowWidth - widePanelMargin - _regularColumnWidth(windowWidth) <
    windowWidth * wideMinMapShare;

/// A wide window shorter than this gets the compact top. A foldable's
/// inner screen on its side (669) has, under the search and a row of
/// chips, too little height for the map's whole control column above the
/// Plan card grown at rest for its time control; an iPad on its side (820)
/// has enough.
const double wideCompactTopHeight = 720;

/// Whether the tab at [context] has the compact top: the search then holds
/// the route profiles as a menu at its end, as on a phone turned sideways,
/// instead of a row of chips under it. So in a compact column, and in a
/// wide window shorter than [wideCompactTopHeight].
bool wideCompactTopOf(BuildContext context) {
  if (!ShellLayout.of(context).widePanel) return false;
  // The window's size: the media here may be the column's.
  MediaQuery.sizeOf(context);
  final view = View.of(context);
  final window = view.physicalSize / view.devicePixelRatio;
  return wideColumnCompact(window.width) ||
      window.height < wideCompactTopHeight;
}

/// Where the column stands in a wide window described by [screen] (the
/// window's own metrics), on [side]: [widePanelMargin] from that side's
/// safe area, as tall as the window.
Rect wideColumnRect(MediaQueryData screen, WideColumnSide side) {
  final window = screen.size;
  final width = widePanelWidth(window.width);
  final padding = screen.padding;
  final left = switch (side) {
    WideColumnSide.left => padding.left + widePanelMargin,
    WideColumnSide.right =>
      window.width - padding.right - widePanelMargin - width,
    WideColumnSide.centre =>
      padding.left + (window.width - padding.horizontal - width) / 2,
  };
  return Rect.fromLTWH(left, 0, width, window.height);
}

/// Where the column of a wide window stands, as [WideAppFrame] says.
WideColumnSide wideColumnSideOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_SideScope>()?.side ??
    WideColumnSide.left;

/// The column of the wide window [context] is in, in the window's
/// coordinates; read from the window, whatever the media at [context].
Rect wideColumnOf(BuildContext context) => wideColumnRect(
  MediaQueryData.fromView(View.of(context)),
  wideColumnSideOf(context),
);

/// Whether the map's controls stand at the window's left edge: in a wide
/// window ([layout]) whose column stands on the left, where they are over
/// the column's map between its chrome and its sheet, as at a phone's
/// right edge. Everywhere else they stand at the right edge.
bool wideMapControlsAtLeft(BuildContext context, ShellLayout layout) =>
    layout.widePanel && wideColumnSideOf(context) == WideColumnSide.left;

/// Whether the column of a wide window ([layout]) stands at one of the
/// window's sides: the tab's chrome at its top, the map's controls and its
/// card then share the column's edge at that side.
bool wideColumnAtSide(BuildContext context, ShellLayout layout) =>
    layout.widePanel && wideColumnSideOf(context) != WideColumnSide.centre;

/// [margin], a phone's between the screen's sides and a map tab's chrome
/// over the map, but with none on the column's outer side when the column
/// stands at a side of a wide window ([wideColumnAtSide]): the chrome is
/// flush with the column's edge there, as the map's controls and the card
/// are.
EdgeInsets wideChromeMargin(BuildContext context, EdgeInsets margin) {
  if (!wideColumnAtSide(context, ShellLayout.of(context))) return margin;
  return wideColumnSideOf(context) == WideColumnSide.left
      ? margin.copyWith(left: 0)
      : margin.copyWith(right: 0);
}

/// What the column and the window's safe areas take from either side of a
/// wide window's map: the map in view is the rest, on the column's far
/// side (the right of a column in the middle).
EdgeInsets wideMapBeside(BuildContext context) {
  final screen = MediaQueryData.fromView(View.of(context));
  final column = wideColumnOf(context);
  return wideColumnSideOf(context) == WideColumnSide.right
      ? EdgeInsets.only(
          left: screen.viewPadding.left,
          right: screen.size.width - column.left,
        )
      : EdgeInsets.only(left: column.right, right: screen.viewPadding.right);
}

/// Whether a window of [size] gets the wide layout, as the shell decides
/// it (a test may have set one layout for every size).
bool _wideAt(Size size) => ShellLayout.resolve(size, RailSide.right).widePanel;

/// How far around the column the shadows of what is in it reach: the
/// navigators in it clip to their boxes, so theirs are this much larger.
const double widePanelShadowRoom = 40;

/// [media] as a phone held upright would have it, for what is laid out in
/// [column] of a wide window: as wide as the column, as tall as the window,
/// with no safe area at its sides. The window's own bottom and top stay,
/// the bar's included.
MediaQueryData _phoneMedia(MediaQueryData media, Rect column) => media.copyWith(
  size: Size(column.width, media.size.height),
  padding: media.padding.copyWith(left: 0, right: 0),
  viewPadding: media.viewPadding.copyWith(left: 0, right: 0),
  viewInsets: media.viewInsets.copyWith(left: 0, right: 0),
  displayFeatures: const <DisplayFeature>[],
);

/// [child] placed in the column of a wide window, which a box of
/// [outer]'s size fills: as wide as the column plus [room] either side and
/// told by its media that it is a phone held upright. Elsewhere [child]
/// filling it, as it is. The same widgets either way, so a window resized
/// across the line keeps [child]'s state.
Widget _inColumn({
  required BuildContext context,
  required bool wide,
  required EdgeInsets room,
  required Widget child,
}) {
  final media = MediaQuery.of(context);
  final column = wide ? wideColumnOf(context) : Rect.zero;
  return Padding(
    padding: EdgeInsets.only(left: wide ? column.left - room.left : 0),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: wide ? column.width + room.horizontal : double.infinity,
        height: double.infinity,
        child: MediaQuery(
          data: wide ? _phoneMedia(media, column) : media,
          child: child,
        ),
      ),
    ),
  );
}

/// A tab in a wide window: its branch's navigator in the column, which
/// tells everything in it that it is a phone held upright. Elsewhere
/// [child] as it is.
class WidePanelColumn extends StatelessWidget {
  /// Creates the column.
  const WidePanelColumn({required this.child, super.key});

  /// The tab: its branch's navigator.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = ShellLayout.of(context).widePanel;
    final room = wide ? _shadowRoom(context) : EdgeInsets.zero;
    return _inColumn(
      context: context,
      wide: wide,
      room: room,
      child: _PanelScope(room: room, child: child),
    );
  }
}

/// The room a navigator in the column is given for the shadows of what it
/// holds, as far as the window reaches either side.
EdgeInsets _shadowRoom(BuildContext context) {
  final column = wideColumnOf(context);
  final width = MediaQueryData.fromView(View.of(context)).size.width;
  return EdgeInsets.only(
    left: math.min(column.left, widePanelShadowRoom),
    right: math.min(width - column.right, widePanelShadowRoom),
  );
}

class _PanelScope extends InheritedWidget {
  const _PanelScope({required this.room, required super.child});

  /// The room around the column for its shadows.
  final EdgeInsets room;

  @override
  bool updateShouldNotify(_PanelScope oldWidget) => oldWidget.room != room;
}

/// A page in a tab's navigator ([WidePanelColumn]): in a wide window
/// inside the room that navigator has for shadows, so the page is the
/// column; elsewhere [child] as it is.
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

class _SideScope extends InheritedWidget {
  const _SideScope({required this.side, required super.child});

  final WideColumnSide side;

  @override
  bool updateShouldNotify(_SideScope oldWidget) => oldWidget.side != side;
}

/// The whole app, around the root navigator, with its column on [side] in
/// a wide window: everything a route lays out where the window's display
/// features let it (a modal sheet, a dialog, a menu) lays out in the
/// column, as on a phone held upright. The window is told that what lies
/// either side of the column are features to keep clear of, as a
/// foldable's hinge is.
class WideAppFrame extends StatelessWidget {
  /// Creates the frame.
  const WideAppFrame({required this.side, required this.child, super.key});

  /// Where the column stands.
  final WideColumnSide side;

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final column = wideColumnRect(media, side);
    Rect band(double from, double to) =>
        Rect.fromLTRB(from, 0, to, size.height);
    // A MediaQuery either way, so a window resized across the line keeps
    // the app's state. In a wide window what opens over the shell opens in
    // the column, where a phone has no safe area at its sides: none is
    // said there, or a modal sheet's own safe area (taken outside the part
    // it is placed in) narrowed the sheet by the system bar's width
    // beside the window. The shell takes the window's back
    // ([WindowSideInsets]).
    return _SideScope(
      side: side,
      child: MediaQuery(
        data: !_wideAt(size)
            ? media
            : media.copyWith(
                padding: media.padding.copyWith(left: 0, right: 0),
                viewPadding: media.viewPadding.copyWith(left: 0, right: 0),
                displayFeatures: <DisplayFeature>[
                  ...media.displayFeatures,
                  for (final bounds in [
                    band(0, column.left),
                    band(column.right, size.width),
                  ])
                    if (bounds.width > 0)
                      DisplayFeature(
                        bounds: bounds,
                        type: DisplayFeatureType.unknown,
                        state: DisplayFeatureState.unknown,
                      ),
                ],
              ),
        child: child,
      ),
    );
  }
}

/// [child] with the window's own safe areas at its sides, which
/// [WideAppFrame] leaves out in a wide window: the shell, whose map and
/// controls reach the window's edges, keeps clear of a system bar there.
/// Elsewhere the media as it is.
class WindowSideInsets extends StatelessWidget {
  /// Creates the insets.
  const WindowSideInsets({required this.child, super.key});

  /// The shell.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!_wideAt(media.size)) return MediaQuery(data: media, child: child);
    final window = MediaQueryData.fromView(View.of(context));
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          left: window.padding.left,
          right: window.padding.right,
        ),
        viewPadding: media.viewPadding.copyWith(
          left: window.viewPadding.left,
          right: window.viewPadding.right,
        ),
      ),
      child: child,
    );
  }
}

/// The app's full pages: a [MaterialPageRoute] whose page, in a wide
/// window, is in the column, coming and going inside it as on a phone
/// inside the screen, with the map in view beside it (the route is not
/// opaque there). Elsewhere a [MaterialPageRoute] as it always was.
class ColumnPageRoute<T> extends MaterialPageRoute<T> {
  /// Creates the route.
  ColumnPageRoute({required super.builder, super.settings});

  bool _wide = false;

  /// Whether the window is a wide one, whichever navigator the page is on:
  /// the page then fades in and out in the column, as a tab does there,
  /// rather than sliding in from the side.
  bool _wideWindow = false;

  /// The page itself, kept through a change of transition when the window
  /// is resized across the line.
  final GlobalKey _pageKey = GlobalKey();

  @override
  bool get opaque => !_wide;

  @override
  Duration get transitionDuration =>
      _wideWindow ? tabFadeDuration : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      _wideWindow ? tabFadeDuration : super.reverseTransitionDuration;

  /// Follows the window the page is laid out in: the map under the page is
  /// kept painted in a wide window, and let go elsewhere.
  void _followWindow({required bool wide}) {
    if (wide == _wide) return;
    _wide = wide;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final entries = overlayEntries;
      if (!isActive || entries.isEmpty) return;
      if (animation?.isCompleted ?? false) entries.first.opaque = opaque;
    });
  }

  @override
  void install() {
    final context = navigator?.context;
    final view = context == null ? null : View.maybeOf(context);
    if (view != null) {
      _wideWindow = _wideAt(view.physicalSize / view.devicePixelRatio);
      // As [_ColumnPage] decides: on the root navigator, not a tab's,
      // which is in the column already.
      _wide =
          context!.getInheritedWidgetOfExactType<_PanelScope>() == null &&
          _wideAt(view.physicalSize / view.devicePixelRatio);
    }
    super.install();
  }

  /// In a wide window the route under the page stays where it is: the
  /// map beside the column is not slid aside, as the page under a page
  /// that covers the screen is (the parallax of Apple's transition, which
  /// a browser on a Mac gets too).
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      !_wide && super.canTransitionFrom(previousRoute);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The window's size, which the media here follows (in a tab's column
    // too), so a resize builds this again.
    MediaQuery.sizeOf(context);
    final view = View.of(context);
    _wideWindow = _wideAt(view.physicalSize / view.devicePixelRatio);
    final page = KeyedSubtree(key: _pageKey, child: child);
    return _ColumnPage(
      route: this,
      child: _wideWindow
          // The tabs' own fade, for a page in the column.
          ? FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: page,
            )
          : super.buildTransitions(
              context,
              animation,
              secondaryAnimation,
              page,
            ),
    );
  }
}

/// A full page of the router's as a [ColumnPageRoute].
class ColumnPage<T> extends Page<T> {
  /// Creates the page.
  const ColumnPage({required this.child, super.key, super.name});

  /// The page's content.
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) =>
      ColumnPageRoute<T>(settings: this, builder: (_) => child);
}

/// A [ColumnPageRoute]'s page with its transition: on the app's root
/// navigator in the column of a wide window; in a tab's navigator, which is
/// in the column already, inside the room that navigator has for shadows.
/// Clipped to the column there, so it slides in and out of it as on a
/// phone. Elsewhere [child] as it is.
class _ColumnPage extends StatelessWidget {
  const _ColumnPage({required this.route, required this.child});

  final ColumnPageRoute<Object?> route;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final room = context
        .dependOnInheritedWidgetOfExactType<_PanelScope>()
        ?.room;
    final wide = room == null && _wideAt(MediaQuery.sizeOf(context));
    route._followWindow(wide: wide);
    final clip = wide || (room != null && room != EdgeInsets.zero);
    return _inColumn(
      context: context,
      wide: wide,
      room: EdgeInsets.zero,
      child: Padding(
        padding: room ?? EdgeInsets.zero,
        // The same widgets either way, clipping or not.
        child: ClipRect(
          clipBehavior: clip ? Clip.hardEdge : Clip.none,
          child: child,
        ),
      ),
    );
  }
}

/// Which of the shell's tabs has a page pushed over it in its branch's
/// navigator (a page the tab opened, the offline data say): in a wide
/// window the map beside the column is then under that page, and takes no
/// touch, as on a phone. Its value changes whenever that may have changed.
class TabPages extends ChangeNotifier implements ValueListenable<int> {
  final List<_TabPagesObserver> _observers = <_TabPagesObserver>[];
  int _changes = 0;

  /// The observer for the next branch's navigator, in the shell's order.
  NavigatorObserver observer() {
    final observer = _TabPagesObserver(this);
    _observers.add(observer);
    return observer;
  }

  /// Whether the tab at [index] has a page over it.
  bool covers(int index) =>
      index < _observers.length && _observers[index]._covered;

  @override
  int get value => _changes;

  void _changed() {
    _changes++;
    notifyListeners();
  }
}

class _TabPagesObserver extends NavigatorObserver {
  _TabPagesObserver(this._owner);

  final TabPages _owner;
  bool _covered = false;

  /// After the frame: a navigator tells of its pages while it builds.
  void _update() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final covered = navigator?.canPop() ?? false;
    if (covered == _covered) return;
    _covered = covered;
    _owner._changed();
  });

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update();
}
