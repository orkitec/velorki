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

  /// Records that the tab at [route] is the one on screen.
  void show(String route) {
    if (!ref.mounted || state == route) return;
    state = route;
  }
}

/// Where the map's control column starts on the Plan and Record tabs, in dp
/// below the safe-area top: one animated value for both, so the two maps,
/// which the shell paints one over the other while a tab change runs, never
/// show the column in two places. The tab on screen tells it where the
/// column rests under its chrome, and it glides there; a ticker of its own,
/// not a tab's, so the glide runs whichever tab is painted on top.
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
