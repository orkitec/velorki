import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell_layout.dart';
import '../application/covering_sheets.dart';
import 'docking_sheet.dart';
import 'floating_bar.dart';

/// The width a sheet turned sideways gives its content at rest: as wide as
/// the narrowest phone held upright gives it.
const double sidewaysSheetContentWidth = 360;

/// How many quarter turns clockwise the bar and the sheets are turned on a
/// screen of [layout]: none upright, so their bottom edge, which is the
/// bar's, lies on the side the phone's bottom edge went to.
int shellQuarterTurns(ShellLayout layout) {
  if (!layout.sideRail) return 0;
  return layout.side == RailSide.left ? 1 : 3;
}

/// [insets] as seen from inside a frame turned [quarterTurns] clockwise: the
/// inset at the frame's own top is the one at the screen side its top lies
/// on.
EdgeInsets turnInsets(EdgeInsets insets, int quarterTurns) =>
    switch (quarterTurns % 4) {
      1 => EdgeInsets.fromLTRB(
        insets.top,
        insets.right,
        insets.bottom,
        insets.left,
      ),
      2 => EdgeInsets.fromLTRB(
        insets.right,
        insets.bottom,
        insets.left,
        insets.top,
      ),
      3 => EdgeInsets.fromLTRB(
        insets.bottom,
        insets.left,
        insets.top,
        insets.right,
      ),
      _ => insets,
    };

/// [child] turned [quarterTurns] clockwise, and told so: its size, safe
/// areas and keyboard inset are the turned ones, so a bar or a sheet built
/// for a phone held upright lays itself out at the turned frame's bottom
/// as it would at the screen's.
///
/// Turned back inside with the opposite count, content is upright again and
/// sees the screen as it is.
///
/// The frame is there at no turns too, doing nothing: a phone turning then
/// changes how far it turns, not what it holds, and a sheet inside keeps its
/// state, and its controller, through the turn.
class QuarterTurnedFrame extends StatelessWidget {
  /// Creates the frame.
  const QuarterTurnedFrame({
    required this.quarterTurns,
    required this.child,
    super.key,
  });

  /// Quarter turns clockwise.
  final int quarterTurns;

  /// What is turned.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final turns = quarterTurns % 4;
    final media = MediaQuery.of(context);
    return RotatedBox(
      quarterTurns: turns,
      child: MediaQuery(
        data: media.copyWith(
          size: turns.isOdd ? media.size.flipped : media.size,
          padding: turnInsets(media.padding, turns),
          viewPadding: turnInsets(media.viewPadding, turns),
          viewInsets: turnInsets(media.viewInsets, turns),
        ),
        child: child,
      ),
    );
  }
}

/// Where a tab's sheet lies and what its extents are, upright or sideways.
///
/// Upright the sheet rises from the bottom over the screen's height, and the
/// floating bar covers [endInset] of it. Sideways it is the same sheet turned
/// a quarter: it comes out from the rail's side over the screen's width, the
/// rail covering [endInset] of it, and its content is turned back upright.
/// A screen sizes its sheet from these numbers in both cases, so the sheet
/// rests, docks and hands over between the tabs alike.
@immutable
class SheetGeometry {
  const SheetGeometry._({
    required this.layout,
    required this.length,
    required this.endInset,
    required this.viewEndInset,
  });

  /// The geometry for the screen at [context]: a tab's, whose padding counts
  /// the bar or the rail the shell lays over it.
  factory SheetGeometry.of(BuildContext context) {
    final layout = ShellLayout.of(context);
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    if (!layout.sideRail) {
      return SheetGeometry._(
        layout: layout,
        length: size.height,
        endInset: padding.bottom,
        viewEndInset: viewPadding.bottom,
      );
    }
    final left = layout.side == RailSide.left;
    return SheetGeometry._(
      layout: layout,
      length: size.width,
      endInset: left ? padding.left : padding.right,
      viewEndInset: left ? viewPadding.left : viewPadding.right,
    );
  }

  /// The geometry a tab's sheet has under the shell's bar or rail, for a
  /// sheet in a route over the shell (a modal sheet on the root navigator),
  /// whose [media] does not count the bar or the rail: so such a sheet can
  /// rest where the tab's sheet rests.
  factory SheetGeometry.overShell(MediaQueryData media, ShellLayout layout) {
    final viewPadding = media.viewPadding;
    if (!layout.sideRail) {
      return SheetGeometry._(
        layout: layout,
        length: media.size.height,
        endInset: viewPadding.bottom + floatingBarBottomGap + floatingBarHeight,
        viewEndInset: viewPadding.bottom,
      );
    }
    final left = layout.side == RailSide.left;
    return SheetGeometry._(
      layout: layout,
      length: media.size.width,
      endInset: floatingRailInset(viewPadding, layout.side),
      viewEndInset: left ? viewPadding.left : viewPadding.right,
    );
  }

  /// The layout the sheet is in.
  final ShellLayout layout;

  /// How far the sheet reaches from its end of the screen at rest, in dp.
  double get restingDp => resting * length;

  /// Whether the sheet is turned sideways.
  bool get sideways => layout.sideRail;

  /// The length of the sheet's travel: the screen's height upright, its
  /// width sideways.
  final double length;

  /// What the bar or the rail covers at the sheet's end, in dp.
  final double endInset;

  /// The safe area alone at the sheet's end, without bar or rail.
  final double viewEndInset;

  /// What the bar covers while a ride hides the navigation and the figures
  /// bar takes its place: the same shape.
  double get figuresBarInset =>
      viewEndInset + floatingBarBottomGap + floatingBarHeight;

  /// [dp] above the sheet's end inset as a fraction of [length].
  double fraction(double dp) =>
      length <= 0 ? 0.5 : ((endInset + dp) / length).clamp(0.01, 0.9);

  /// Where the sheet is docked over a bar covering [barInset]: only its
  /// handle strip beside it.
  double collapsedFor(double barInset) => length <= 0
      ? 0.1
      : ((barInset + sheetHandleDp) / length).clamp(
          0.01,
          sideways ? 0.5 : 0.25,
        );

  /// See [collapsedFor], with the bar or rail in place.
  double get collapsed => collapsedFor(endInset);

  /// The travel over which the sheet morphs into the docked pill.
  double get dockedRange => length <= 0 ? 0.15 : sheetDockingRangeDp / length;

  /// Where the sheets rest: upright as [sheetRestingExtent] says; sideways
  /// as wide as an upright phone gives the content, beside the rail.
  double get resting => sideways
      ? fraction(sheetHandleDp + sidewaysSheetContentWidth).clamp(0.3, 0.75)
      : sheetRestingExtent(length);
}

/// A sheet's three stops: docked, at rest and all the way open.
@immutable
class SheetStops {
  /// Creates the stops.
  const SheetStops({
    required this.collapsed,
    required this.resting,
    required this.max,
  });

  /// Docked: [DraggableScrollableSheet.minChildSize].
  final double collapsed;

  /// At rest: the snap point.
  final double resting;

  /// All the way open: [DraggableScrollableSheet.maxChildSize].
  final double max;
}

/// [extent], a sheet's size among the stops [from], moved to the same place
/// among the stops [to]: a sheet docked, at rest or all the way open stays
/// so, and one between two stops keeps its share of the way between them.
double mapSheetExtent(
  double extent, {
  required SheetStops from,
  required SheetStops to,
}) {
  // A hair off a stop is on it: a snap or a clamp leaves no more.
  const near = 0.005;
  if ((extent - from.resting).abs() < near) return to.resting;
  if (extent <= from.collapsed + near) return to.collapsed;
  if (extent >= from.max - near) return to.max;
  double between(double a, double b, double c, double d) =>
      b - a <= 0 ? c : c + (extent - a) / (b - a) * (d - c);
  final mapped = extent < from.resting
      ? between(from.collapsed, from.resting, to.collapsed, to.resting)
      : between(from.resting, from.max, to.resting, to.max);
  return mapped.clamp(to.collapsed, to.max);
}

/// How long a tab's sheet takes to go down out from behind a modal sheet
/// opening over it, and to come back once the modal sheet has closed.
const Duration coveredSheetDuration = Duration(milliseconds: 250);

/// A tab's sheet: the bottom sheet that docks in the bar, built as it always
/// was; on a phone turned sideways the same sheet turned a quarter with the
/// bar, coming out from the rail's side, its content turned back upright.
///
/// Every argument is the sheet's own, sized from a [SheetGeometry], so the
/// sheet behaves the same either way: it rests, snaps, docks into the bar
/// (the rail, sideways) and reports its extent as it always has.
///
/// A turn of the phone changes what an extent means, a share of the
/// screen's height upright and of its width sideways, and every point the
/// sheet snaps to with it. The sheet keeps where the rider left it instead:
/// docked stays docked, at rest stays at rest, pulled open stays as far
/// open; see [mapSheetExtent].
///
/// With [collapseWhenCovered], upright, the sheet goes down to
/// [coveredExtent] while a modal sheet is open over the tab (counted by
/// [coveringSheetsProvider]), so it does not peek out behind it, and comes
/// back to exactly where it was once the last one has closed.
class AdaptiveDockingSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const AdaptiveDockingSheet({
    required this.controller,
    required this.initialExtent,
    required this.collapsedExtent,
    required this.maxExtent,
    required this.snapSizes,
    required this.dockedRange,
    required this.docks,
    required this.dockedBottomInset,
    required this.child,
    this.gripDp = sheetHandleDp,
    this.contentEndInset,
    this.onDocked,
    this.onExtent,
    this.sheetKey,
    this.boxKey,
    this.collapseWhenCovered = false,
    this.coveredExtent,
    this.coveredReturnExtent,
    super.key,
  });

  /// The sheet's controller.
  final DraggableScrollableController controller;

  /// See [DraggableScrollableSheet.initialChildSize].
  final double initialExtent;

  /// See [DraggableScrollableSheet.minChildSize]: docked.
  final double collapsedExtent;

  /// See [DraggableScrollableSheet.maxChildSize].
  final double maxExtent;

  /// See [DraggableScrollableSheet.snapSizes].
  final List<double>? snapSizes;

  /// See [DockingSheet.dockedRange].
  final double dockedRange;

  /// See [DockingSheet.docks].
  final bool docks;

  /// See [DockingSheet.dockedBottomInset]: the bar's, or the rail's.
  final double dockedBottomInset;

  /// See [DockingSheet.gripDp].
  final double gripDp;

  /// What the content keeps clear of at the sheet's end sideways, where it
  /// is turned upright beside the rail: [dockedBottomInset] by default. A
  /// sheet that docks into a bar that only shows once it is docked (the
  /// figures bar of a ride) keeps clear of what is there while it is open.
  final double? contentEndInset;

  /// See [DockingSheet.onDocked].
  final ValueChanged<bool>? onDocked;

  /// See [DockingSheet.onExtent].
  final ValueChanged<double>? onExtent;

  /// The key of the sheet itself, to start it afresh.
  final Key? sheetKey;

  /// The key of the sheet's box, the [DockingSheet].
  final Key? boxKey;

  /// The content; it reads its scroll controller from [SheetContentScroll].
  final Widget child;

  /// Whether the sheet goes down while a modal sheet covers the tab: the
  /// tab on screen's sheet does, a tab's away does not. Sideways nothing
  /// moves, whatever this says.
  final bool collapseWhenCovered;

  /// Where the sheet goes down to while covered: [collapsedExtent] by
  /// default. A sheet already lower stays where it is.
  final double? coveredExtent;

  /// Where the sheet comes back to once uncovered, asked as the cover
  /// begins: its size then by default. A screen that has moved the sheet
  /// out of the way for a while of its own (under the keyboard) names the
  /// place it would have brought it back to.
  final ValueGetter<double>? coveredReturnExtent;

  /// Where the sheet rests: its snap point, or where it starts without one.
  double get restingExtent => snapSizes?.firstOrNull ?? initialExtent;

  @override
  ConsumerState<AdaptiveDockingSheet> createState() =>
      _AdaptiveDockingSheetState();
}

class _AdaptiveDockingSheetState extends ConsumerState<AdaptiveDockingSheet> {
  /// The screen, its safe areas and the turn the sheet was last built for,
  /// with its stops. The safe areas move with a turn too, a frame or two
  /// after the size; the keyboard moves neither. The phone's own, not the
  /// screen's, which the bar coming and going with the keyboard changes.
  Size? _screen;
  EdgeInsets? _safe;
  int? _turns;
  SheetStops? _stops;

  /// The phone has turned since the last build: the sheet is moved, after
  /// this frame, to the same place among the new stops as it had among the
  /// old ones.
  ///
  /// Left to itself, a [DraggableScrollableSheet] keeps the old share of
  /// the screen and, once the rider has dragged it, snaps from there to the
  /// nearest point after every build that brings it a new list of them. A
  /// turn brings one each frame it animates through, and the snaps pile
  /// up: their moves add up and overshoot, and the sheet climbed a step a
  /// turn until it was all the way open. A jump puts it where it belongs
  /// and, being no drag, stops the snapping until the rider drags again.
  void _keepPlace(SheetStops from, SheetStops to) {
    final controller = widget.controller;
    if (!controller.isAttached) return;
    // Read now, before the sheet below takes the new stops and clamps.
    final target = mapSheetExtent(controller.size, from: from, to: to);
    // Registered before the sheet's own snap, so it runs first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.isAttached) return;
      controller.jumpTo(target);
    });
  }

  @override
  void didUpdateWidget(AdaptiveDockingSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new sheet starts afresh; there is no place to keep.
    if (oldWidget.controller != widget.controller ||
        oldWidget.sheetKey != widget.sheetKey) {
      _stops = null;
      _beforeCover = null;
    }
  }

  /// Where the sheet was before a modal sheet covered the tab, among the
  /// stops it had then; `null` while it has not been lowered for one.
  (double, SheetStops)? _beforeCover;

  void _onCovering(int? previous, int next) {
    final before = previous ?? 0;
    if (before == 0 && next > 0) {
      _lower();
    } else if (before > 0 && next == 0) {
      _raise();
    }
  }

  /// A modal sheet opens over the tab: the sheet goes down out from behind
  /// it, remembering where it was.
  void _lower() {
    final controller = widget.controller;
    final stops = _stops;
    if (!mounted ||
        !widget.collapseWhenCovered ||
        !controller.isAttached ||
        stops == null ||
        _beforeCover != null ||
        ShellLayout.of(context).sideRail) {
      return;
    }
    const near = 0.005;
    final target = widget.coveredExtent ?? widget.collapsedExtent;
    final size = controller.size;
    final back = widget.coveredReturnExtent?.call() ?? size;
    // Down already, and to stay there.
    if (size <= target + near && back <= target + near) return;
    _beforeCover = (back, stops);
    if (size > target + near) _move(target);
  }

  /// The last modal sheet has closed: the sheet comes back to where it
  /// was, wherever the rider may have pulled it meanwhile, and to the same
  /// place among its stops should the phone have turned.
  void _raise() {
    final before = _beforeCover;
    _beforeCover = null;
    if (before == null || !mounted || !widget.controller.isAttached) return;
    final (extent, stops) = before;
    _move(mapSheetExtent(extent, from: stops, to: _stops ?? stops));
  }

  void _move(double extent) {
    final controller = widget.controller;
    if ((controller.size - extent).abs() < 0.001) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpTo(extent);
    } else {
      unawaited(
        controller.animateTo(
          extent,
          duration: coveredSheetDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(coveringSheetsProvider, _onCovering);
    final layout = ShellLayout.of(context);
    final turns = shellQuarterTurns(layout);
    final screen = MediaQuery.sizeOf(context);
    final view = View.of(context);
    final safe = EdgeInsets.fromViewPadding(
      view.viewPadding,
      view.devicePixelRatio,
    );
    final stops = SheetStops(
      collapsed: widget.collapsedExtent,
      resting: widget.restingExtent,
      max: widget.maxExtent,
    );
    final before = _stops;
    if (before != null &&
        (screen != _screen || safe != _safe || turns != _turns)) {
      _keepPlace(before, stops);
    }
    _screen = screen;
    _safe = safe;
    _turns = turns;
    _stops = stops;
    // Sideways the turned sheet's bottom lies under the rail: the content,
    // upright again, keeps clear of it there as a list upright keeps its
    // last row above the bar.
    // The same widgets upright, turned by nothing and padded by nothing, so
    // the content keeps its state through a turn of the phone.
    final sideways = turns != 0;
    final end = sideways
        ? widget.contentEndInset ?? widget.dockedBottomInset
        : 0.0;
    final content = QuarterTurnedFrame(
      quarterTurns: 4 - turns,
      // Upright the handle strip lies above the content; turned, it lies
      // beside it, and the content keeps the strip's air at its top.
      child: Padding(
        padding: layout.side == RailSide.left && sideways
            ? EdgeInsets.only(left: end, top: sheetHandleDp / 2)
            : EdgeInsets.only(
                right: end,
                top: sideways ? sheetHandleDp / 2 : 0,
              ),
        child: FadeTransition(
          // After a turn the content fades back in inside the sheet, which
          // itself stays in view: the same sheet, only turned.
          opacity: ShellLayoutHost.turnFadeOf(context),
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: sideways,
            removeRight: sideways,
            // Sideways a sheet folding away narrows its content where upright
            // it only shortens it: the content keeps its width at rest and is
            // covered from the map's side, as upright it is from the top.
            child: !sideways
                ? widget.child
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= sidewaysSheetContentWidth) {
                        return widget.child;
                      }
                      return ClipRect(
                        child: OverflowBox(
                          minWidth: sidewaysSheetContentWidth,
                          maxWidth: sidewaysSheetContentWidth,
                          alignment: layout.side == RailSide.left
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: widget.child,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
    return QuarterTurnedFrame(
      quarterTurns: turns,
      child: DraggableScrollableSheet(
        key: widget.sheetKey,
        controller: widget.controller,
        initialChildSize: widget.initialExtent,
        minChildSize: widget.collapsedExtent,
        maxChildSize: widget.maxExtent,
        snap: true,
        snapSizes: widget.snapSizes,
        builder: (context, scrollController) => DockingSheet(
          key: widget.boxKey,
          controller: scrollController,
          gripDp: widget.gripDp,
          initialExtent: widget.initialExtent,
          collapsedExtent: widget.collapsedExtent,
          dockedRange: widget.dockedRange,
          docks: widget.docks,
          dockedBottomInset: widget.dockedBottomInset,
          onDocked: widget.onDocked,
          onExtent: widget.onExtent,
          currentExtent: () =>
              widget.controller.isAttached ? widget.controller.size : null,
          handle: const SheetHandle(),
          child: content,
        ),
      ),
    );
  }
}

/// What a sheet beside the rail covers of a sideways screen described by
/// [media], from the rail's edge: the rail, the sheet's handle and, at rest,
/// its content. Zero upright.
double sidewaysSheetCover(
  MediaQueryData media,
  ShellLayout layout, {
  required bool docked,
}) {
  if (!layout.sideRail) return 0;
  final rail = floatingRailInset(media.viewPadding, layout.side);
  return rail + sheetHandleDp + (docked ? 0 : sidewaysSheetContentWidth);
}

/// How far below the safe area's top the map's top row stands on a phone
/// turned sideways: the search, with the profile menu in it, and the map's
/// controls.
const double sidewaysTopRowTop = 8;

/// The height of that row: the search field's, which the controls' row is
/// as tall as.
const double sidewaysTopRowHeight = 56;

/// The air the row keeps from the docked sheet.
const double sidewaysTopRowGap = 12;

/// How far from the screen's far edge, away from the rail, the row's far
/// end (the search) stops: that edge's safe area left out, since the
/// camera's island sits in the middle of that edge, below the row, and the
/// field's rounded end stays inside the screen's rounded corner.
const double sidewaysTopRowFarEdge = 16;

/// Where the map's top row starts on a sideways screen described by [media],
/// from the rail's edge: beside the docked sheet, rail and handle strip,
/// with [sidewaysTopRowGap] of air. During a ride the figures bar takes the
/// rail's place with the rail's width, so the row starts there too. What
/// the row puts at this end, the controls, lies under the sheet at rest;
/// only the search reaches beyond it.
double sidewaysTopRowStart(MediaQueryData media, ShellLayout layout) =>
    sidewaysSheetCover(media, layout, docked: true) + sidewaysTopRowGap;

/// [child] kept clear of the resting sheet on a phone turned sideways:
/// padded on the rail's side by the sheet's handle and content, the rail's
/// own part being padding [child] keeps already. Upright, [child] as it is:
/// the sheet lies below the chrome there.
class BesideSheet extends StatelessWidget {
  /// Creates the wrapper.
  const BesideSheet({required this.child, super.key});

  /// What stands beside the sheet.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = ShellLayout.of(context);
    if (!layout.sideRail) return child;
    const beside = sheetHandleDp + sidewaysSheetContentWidth;
    return Padding(
      padding: layout.side == RailSide.left
          ? const EdgeInsets.only(left: beside)
          : const EdgeInsets.only(right: beside),
      child: child,
    );
  }
}

/// [child], a tab's sheet or the AI's card over it, slid [hidden] of
/// the way out of view along its travel: down past the screen's bottom
/// upright, out past the rail's edge sideways. [distance] is how far out of
/// view is, in dp: as far as the sheet reaches now, so a card let go half
/// way down by the rider goes on from there.
///
/// Only moved, never resized or barred: what the sheet leaves free is the
/// map's all the way through, and the sheet keeps its size and place to
/// come back to.
class SheetSlide extends StatelessWidget {
  /// Creates the slide.
  const SheetSlide({
    required this.hidden,
    required this.distance,
    required this.child,
    super.key,
  });

  /// 0 in view, 1 out of view.
  final Animation<double> hidden;

  /// How far out of view is, in dp, read every frame.
  final ValueGetter<double> distance;

  /// The sheet.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final turns = shellQuarterTurns(ShellLayout.of(context));
    return AnimatedBuilder(
      animation: hidden,
      child: child,
      builder: (context, child) {
        final away = hidden.value * distance();
        return Transform.translate(
          offset: switch (turns) {
            1 => Offset(-away, 0),
            3 => Offset(away, 0),
            _ => Offset(0, away),
          },
          child: child,
        );
      },
    );
  }
}
