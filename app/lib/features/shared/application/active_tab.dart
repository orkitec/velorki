import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/router.dart';
import '../../map/presentation/map_chrome.dart';
import '../presentation/tab_chrome_slide.dart';

part 'active_tab.g.dart';

/// The tab the shell shows, by route path.
///
/// The shell keeps every tab alive in an indexed stack, so a screen never
/// learns from its own lifecycle that it went off screen or came back. It
/// learns it from here: the bar writes the tab as it is tapped, the shell
/// confirms it after every rebuild (the system back gesture changes tabs
/// without a tap), and the Plan and Record screens animate their chrome on
/// the change.
@Riverpod(keepAlive: true)
class ActiveTab extends _$ActiveTab {
  @override
  String build() => plannerRoute;

  /// The tab that was on screen before the current one, or `null` before
  /// any change: a screen built for the first time in the middle of a change
  /// (its tab's first visit) learns from this what it is arriving from.
  String? get previous => _previous;
  String? _previous;

  /// Records that the tab at [route] is the one on screen.
  void show(String route) {
    if (!ref.mounted || state == route) return;
    _previous = state;
    state = route;
  }
}

/// Where the shell's control column starts over the map the Plan and Record
/// tabs share, in dp below the safe-area top: one animated value for both
/// tabs. The tab on screen tells it where the column rests under its
/// chrome, and it glides there; a ticker of its own, not a tab's, so the
/// glide runs whichever tab is painted on top.
@Riverpod(keepAlive: true)
ValueGlide mapControlsTop(Ref ref) {
  final glide = ValueGlide(
    vsync: const _FreeTicker(),
    initial: defaultMapControlsTop,
  );
  ref.onDispose(glide.dispose);
  return glide;
}

/// A ticker bound to no widget, so no [TickerMode] mutes it.
class _FreeTicker implements TickerProvider {
  const _FreeTicker();

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// What the tab on screen has done with the sheet the Plan and Record tabs
/// share over their maps, so the next tab can pick it up where it is and
/// animate to its own arrangement rather than swap in with a jump.
@immutable
class TabChrome {
  const TabChrome({this.sheetExtent});

  /// The sheet's extent, as a fraction of the screen; `null` before any
  /// sheet has reported one.
  final double? sheetExtent;

  @override
  bool operator ==(Object other) =>
      other is TabChrome && other.sheetExtent == sheetExtent;

  @override
  int get hashCode => sheetExtent.hashCode;
}

/// The [TabChrome] of the tab on screen. Only that tab writes it; a tab
/// coming on screen reads it once to start its animations from there.
@Riverpod(keepAlive: true)
class TabHandover extends _$TabHandover {
  @override
  TabChrome build() => const TabChrome();

  /// Where the sheet of the tab on screen is.
  void setSheetExtent(double value) {
    if (!ref.mounted || state.sheetExtent == value) return;
    state = TabChrome(sheetExtent: value);
  }
}

/// What the tab on screen wants of the shell's control column: the same
/// facts a [MapChromeInsets] carries to an in-map column, plus whether the
/// column is wanted at all (a battery-saver ride's glance view has no map).
@immutable
class MapChromeData {
  const MapChromeData({
    this.visible = true,
    this.showRoutingTiles = true,
    this.following = false,
    this.headingUp = false,
    this.bearingDeg = 0,
    this.onLocate,
    this.onCompass,
    this.routeShown = false,
    this.onToggleRoute,
  });

  final bool visible;
  final bool showRoutingTiles;
  final bool following;
  final bool headingUp;
  final double bearingDeg;
  final VoidCallback? onLocate;
  final VoidCallback? onCompass;
  final bool routeShown;
  final VoidCallback? onToggleRoute;

  @override
  bool operator ==(Object other) =>
      other is MapChromeData &&
      other.visible == visible &&
      other.showRoutingTiles == showRoutingTiles &&
      other.following == following &&
      other.headingUp == headingUp &&
      other.bearingDeg == bearingDeg &&
      other.onLocate == onLocate &&
      other.onCompass == onCompass &&
      other.routeShown == routeShown &&
      other.onToggleRoute == onToggleRoute;

  @override
  int get hashCode => Object.hash(
    visible,
    showRoutingTiles,
    following,
    headingUp,
    bearingDeg,
    onLocate,
    onCompass,
    routeShown,
    onToggleRoute,
  );
}

/// The [MapChromeData] of the tab on screen, written by that tab after each
/// build that changes it.
@Riverpod(keepAlive: true)
class ActiveMapChrome extends _$ActiveMapChrome {
  @override
  MapChromeData? build() => null;

  /// Records what the tab on screen wants of the column.
  void set(MapChromeData? data) {
    if (!ref.mounted || state == data) return;
    state = data;
  }
}
