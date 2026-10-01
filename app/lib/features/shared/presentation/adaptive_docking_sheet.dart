import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/shell_layout.dart';
import '../../../app/theme.dart';
import 'docking_sheet.dart';
import 'floating_bar.dart';

part 'adaptive_docking_sheet.g.dart';

/// The width of the side panel a sheet becomes on a phone turned sideways.
const double sidePanelWidth = 380;

/// The width of the side panel's grip: all that is left of it folded away
/// against the rail.
const double sidePanelGripWidth = 28;

/// The side panel never takes more than this share of the tab's width, so
/// some map stays beside it on the smallest phone.
const double sidePanelMaxShare = 0.62;

/// The width the side panel takes in a tab [tabWidth] wide.
double sidePanelWidthFor(double tabWidth) => tabWidth <= 0
    ? sidePanelWidth
    : sidePanelWidth.clamp(0, tabWidth * sidePanelMaxShare);

/// How much of a tab [tabWidth] wide the side panel shows at open fraction
/// [open]: its grip folded away, its whole width open.
double sidePanelVisibleWidth(double tabWidth, double open) {
  final width = sidePanelWidthFor(tabWidth);
  return sidePanelGripWidth +
      (width - sidePanelGripWidth) * open.clamp(0.0, 1.0);
}

/// What the rail and a side panel open by [open] cover of a sideways screen
/// described by [media], from its edges; [EdgeInsets.zero] upright. The map
/// is what lies between.
EdgeInsets sideCover(MediaQueryData media, ShellLayout layout, double open) {
  if (!layout.sideRail) return EdgeInsets.zero;
  final rail = floatingRailInset(media.viewPadding, layout.side);
  final cover = rail + sidePanelVisibleWidth(media.size.width - rail, open);
  return layout.side == RailSide.left
      ? EdgeInsets.only(left: cover)
      : EdgeInsets.only(right: cover);
}

/// How far the side panel on screen is open, 0 folded away to 1 open, as it
/// moves: for what stands beside it (the control column) and what is
/// measured against it (the camera's padding). Written by the panel of the
/// tab on screen only.
@Riverpod(keepAlive: true)
ValueNotifier<double> sidePanelFraction(Ref ref) {
  final fraction = ValueNotifier<double>(
    ref.read(sidePanelOpenProvider) ? 1 : 0,
  );
  ref.onDispose(fraction.dispose);
  return fraction;
}

/// Whether the side panels of the map tabs are open, one answer for all of
/// them: a panel folded away on Plan is folded away on Record too, as a
/// docked sheet stays docked across the tabs upright.
@Riverpod(keepAlive: true)
class SidePanelOpen extends _$SidePanelOpen {
  @override
  bool build() => true;

  /// Records whether the panels are open.
  void set(bool open) {
    if (open != state) state = open;
  }
}

/// A tab's sheet: the bottom sheet that docks in the bar on a phone held
/// upright, and a panel beside the rail on a phone turned sideways.
///
/// Upright this is exactly a [DraggableScrollableSheet] around a
/// [DockingSheet], built from the same arguments. Sideways it is a
/// [SidePanel] with the same content; no sheet is attached to [controller]
/// then, so a screen's own moves of its sheet, which all ask
/// `isAttached` first, leave the panel alone.
class AdaptiveDockingSheet extends StatelessWidget {
  /// Creates the sheet.
  const AdaptiveDockingSheet({
    required this.controller,
    required this.initialExtent,
    required this.collapsedExtent,
    required this.restingExtent,
    required this.maxExtent,
    required this.snapSizes,
    required this.dockedRange,
    required this.docks,
    required this.dockedBottomInset,
    required this.child,
    this.gripDp = sheetHandleDp,
    this.onDocked,
    this.onExtent,
    this.sheetKey,
    this.boxKey,
    super.key,
  });

  /// The sheet's controller, attached only while it is a bottom sheet.
  final DraggableScrollableController controller;

  /// See [DraggableScrollableSheet.initialChildSize].
  final double initialExtent;

  /// See [DraggableScrollableSheet.minChildSize]: docked.
  final double collapsedExtent;

  /// Where the sheet rests; what an open side panel reports as its extent.
  final double restingExtent;

  /// See [DraggableScrollableSheet.maxChildSize].
  final double maxExtent;

  /// See [DraggableScrollableSheet.snapSizes].
  final List<double>? snapSizes;

  /// See [DockingSheet.dockedRange].
  final double dockedRange;

  /// See [DockingSheet.docks].
  final bool docks;

  /// See [DockingSheet.dockedBottomInset].
  final double dockedBottomInset;

  /// See [DockingSheet.gripDp].
  final double gripDp;

  /// See [DockingSheet.onDocked]; the side panel reports folded away as
  /// docked.
  final ValueChanged<bool>? onDocked;

  /// See [DockingSheet.onExtent]; the side panel reports [restingExtent]
  /// open, [collapsedExtent] folded away and the way between in between.
  final ValueChanged<double>? onExtent;

  /// The key of the bottom sheet itself, to start it afresh.
  final Key? sheetKey;

  /// The key of the sheet's box: the [DockingSheet] upright, the panel
  /// sideways.
  final Key? boxKey;

  /// The content; it reads its scroll controller from [SheetContentScroll].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = ShellLayout.of(context);
    if (layout.sideRail) {
      return SidePanel(
        key: boxKey,
        side: layout.side,
        collapsedExtent: collapsedExtent,
        restingExtent: restingExtent,
        docks: docks,
        onDocked: onDocked,
        onExtent: onExtent,
        child: child,
      );
    }
    return DraggableScrollableSheet(
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
        child: child,
      ),
    );
  }
}

/// A tab's sheet as a panel standing beside the rail, the full height of the
/// screen, on a phone turned sideways.
///
/// A drag sideways folds it away against the rail until only its grip is
/// left, and pulls it out again; a tap on the folded grip opens it. Whether
/// the panels are open is shared by the tabs ([sidePanelOpenProvider]).
class SidePanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const SidePanel({
    required this.side,
    required this.collapsedExtent,
    required this.restingExtent,
    required this.child,
    this.docks = true,
    this.onDocked,
    this.onExtent,
    super.key,
  });

  /// The side of the tab the rail is on, which the panel stands against.
  final RailSide side;

  /// What the panel reports folded away.
  final double collapsedExtent;

  /// What the panel reports open.
  final double restingExtent;

  /// Whether folding away counts as docked (see [onDocked]).
  final bool docks;

  /// Called when the panel is folded away all the way, or no longer is.
  final ValueChanged<bool>? onDocked;

  /// Called with the extent the panel stands for, as a bottom sheet would.
  final ValueChanged<double>? onExtent;

  /// The content.
  final Widget child;

  @override
  ConsumerState<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends ConsumerState<SidePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: ref.read(sidePanelOpenProvider) ? 1 : 0,
  )..addListener(_report);

  final ScrollController _scroll = ScrollController();

  bool? _docked;
  double? _extent;

  /// The panel's width while a drag is under way, to turn pixels into the
  /// open fraction.
  double _width = sidePanelWidth;

  @override
  void initState() {
    super.initState();
    // After the frame, not from it: the owner may rebuild its map for this.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report();
    });
  }

  void _report() {
    final t = _open.value;
    // Only the tab on screen says where the panel is: the others follow
    // the shared open state in a jump, and would undo a fold under way.
    if (mounted && TickerMode.valuesOf(context).enabled) {
      ref.read(sidePanelFractionProvider).value = t;
    }
    final extent = lerpDouble(widget.collapsedExtent, widget.restingExtent, t)!;
    if (extent != _extent) {
      _extent = extent;
      widget.onExtent?.call(extent);
    }
    final docked = widget.docks && t <= 1 - sheetDockedThreshold;
    if (docked != _docked) {
      _docked = docked;
      widget.onDocked?.call(docked);
    }
  }

  /// Moves the panel to open or folded away, and tells the other tabs.
  void _settle(bool open) {
    ref.read(sidePanelOpenProvider.notifier).set(open);
    if (open) {
      _open.forward();
    } else {
      _open.reverse();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final travel = _width - sidePanelGripWidth;
    if (travel <= 0) return;
    // Towards the rail folds the panel away.
    final towardsRail = widget.side == RailSide.right
        ? details.primaryDelta!
        : -details.primaryDelta!;
    _open.value -= towardsRail / travel;
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final towardsRail = widget.side == RailSide.right ? velocity : -velocity;
    if (towardsRail.abs() > 300) {
      _settle(towardsRail < 0);
    } else {
      _settle(_open.value >= 0.5);
    }
  }

  @override
  void dispose() {
    _open.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _onScreen = false;

  @override
  Widget build(BuildContext context) {
    // The tab coming on screen says where its panel is.
    final onScreen = TickerMode.valuesOf(context).enabled;
    if (onScreen && !_onScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _report();
      });
    }
    _onScreen = onScreen;
    // Another tab folded or opened the panels while this one was away.
    ref.listen(sidePanelOpenProvider, (_, open) {
      if (open != (_open.value >= 0.5)) _open.value = open ? 1 : 0;
    });
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final padding = MediaQuery.paddingOf(context);
    final right = widget.side == RailSide.right;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = sidePanelWidthFor(constraints.maxWidth);
        _width = width;
        return ClipRect(
          child: Align(
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: _open,
              builder: (context, child) {
                final t = _open.value;
                // Folding away slides the panel under the tab's edge by the
                // rail until its grip is all that shows.
                final hidden = (width - sidePanelGripWidth) * (1 - t);
                return Transform.translate(
                  offset: Offset(right ? hidden : -hidden, 0),
                  child: child,
                );
              },
              child: SizedBox(
                width: width,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: padding.top + 8,
                    bottom: padding.bottom + 8,
                  ),
                  child: GestureDetector(
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: _onDragEnd,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: colors.glassBorder),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 24,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Material(
                          type: MaterialType.transparency,
                          // The grip lies over the content's margin on the
                          // map side, so the content keeps the panel's whole
                          // width, as wide as on the narrowest phone upright.
                          child: Stack(
                            children: [
                              Positioned.fill(child: _body()),
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: right ? 0 : null,
                                right: right ? null : 0,
                                child: _Grip(
                                  onTap: () => _settle(_open.value < 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body() => AnimatedBuilder(
    animation: _open,
    builder: (context, child) =>
        Opacity(opacity: _open.value.clamp(0.0, 1.0), child: child),
    child: SheetContentScroll(
      controller: _scroll,
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: widget.child,
        ),
      ),
    ),
  );
}

/// The strip on the panel's map side, what stays in view folded away: the
/// handle turned on its side. A tap on it opens or folds the panel.
class _Grip extends StatelessWidget {
  const _Grip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: sidePanelGripWidth,
      child: Center(
        child: Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );
}

/// [child] kept clear of the side panel on a phone turned sideways: padded
/// on the rail's side by as much of the panel as shows, following it as it
/// folds. Upright, [child] as it is.
class BesideSidePanel extends ConsumerWidget {
  /// Creates the wrapper.
  const BesideSidePanel({required this.child, super.key});

  /// What stands beside the panel.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ShellLayout.of(context);
    if (!layout.sideRail) return child;
    final fraction = ref.watch(sidePanelFractionProvider);
    final left = layout.side == RailSide.left;
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<double>(
        valueListenable: fraction,
        builder: (context, open, child) {
          final beside = sidePanelVisibleWidth(constraints.maxWidth, open);
          return Padding(
            padding: left
                ? EdgeInsets.only(left: beside)
                : EdgeInsets.only(right: beside),
            child: child,
          );
        },
        child: child,
      ),
    );
  }
}
