import 'package:flutter/material.dart';

import '../../../app/shell_layout.dart';
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

  /// The layout the sheet is in.
  final ShellLayout layout;

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

/// A tab's sheet: the bottom sheet that docks in the bar, built as it always
/// was; on a phone turned sideways the same sheet turned a quarter with the
/// bar, coming out from the rail's side, its content turned back upright.
///
/// Every argument is the sheet's own, sized from a [SheetGeometry], so the
/// sheet behaves the same either way: it rests, snaps, docks into the bar
/// (the rail, sideways) and reports its extent as it always has.
class AdaptiveDockingSheet extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final layout = ShellLayout.of(context);
    final turns = shellQuarterTurns(layout);
    // Sideways the turned sheet's bottom lies under the rail: the content,
    // upright again, keeps clear of it there as a list upright keeps its
    // last row above the bar.
    // The same widgets upright, turned by nothing and padded by nothing, so
    // the content keeps its state through a turn of the phone.
    final sideways = turns != 0;
    final end = sideways ? contentEndInset ?? dockedBottomInset : 0.0;
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
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: sideways,
          removeRight: sideways,
          // Sideways a sheet folding away narrows its content where upright
          // it only shortens it: the content keeps its width at rest and is
          // covered from the map's side, as upright it is from the top.
          child: !sideways
              ? child
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= sidewaysSheetContentWidth) {
                      return child;
                    }
                    return ClipRect(
                      child: OverflowBox(
                        minWidth: sidewaysSheetContentWidth,
                        maxWidth: sidewaysSheetContentWidth,
                        alignment: layout.side == RailSide.left
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: child,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
    return QuarterTurnedFrame(
      quarterTurns: turns,
      child: DraggableScrollableSheet(
        key: sheetKey,
        controller: controller,
        initialChildSize: initialExtent,
        minChildSize: collapsedExtent,
        maxChildSize: maxExtent,
        snap: true,
        snapSizes: snapSizes,
        builder: (context, scrollController) => DockingSheet(
          key: boxKey,
          controller: scrollController,
          gripDp: gripDp,
          initialExtent: initialExtent,
          collapsedExtent: collapsedExtent,
          dockedRange: dockedRange,
          docks: docks,
          dockedBottomInset: dockedBottomInset,
          onDocked: onDocked,
          onExtent: onExtent,
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
