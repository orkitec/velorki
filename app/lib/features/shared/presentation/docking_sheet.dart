import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// The height of a sheet's handle strip: the drag handle with its margins.
const double sheetHandleDp = 28;

/// The grip of a sheet whose title row has nothing to tap: the strip and the
/// title, so a swipe up on the title moves the sheet.
const double sheetGripWithTitleDp = sheetHandleDp + 60;

/// How far above its collapsed size a sheet travels while it morphs between
/// the full-width sheet and the pill docked in the navigation bar.
const double sheetDockingRangeDp = 220;

/// The corner radius of the docked pill, the sheet's strip and the bar in
/// one: rounder than the bar's own 30, since the docked pill is taller and
/// the same radius read tighter on it. The strip is shorter than this, so
/// its clip scales the radius to its height and the top reads as a full
/// half-round.
const double dockedPillRadius = 40;

/// The [DockingSheetShell.docked] fraction from which a sheet counts as
/// docked: the hairline under the handle appears and the bar squares its top
/// corners.
const double sheetDockedThreshold = 0.99;

/// How far the docked strip reaches down over the bar's top edge, so the
/// seam between the two is one piece of glass rather than a line.
const double sheetDockedOverlapDp = 1;

/// Where the Plan and Record sheets rest, as a fraction of a [screenHeight]
/// tall screen: enough for the Plan headline, a row of variant chips, the
/// toolbar and Save above the navigation bar on a 20:9 phone. One height
/// for both tabs, with or without a route, so the sheet never jumps when a
/// route or a variant arrives or the tab changes; Record's idle content
/// scrolls where it needs more.
double sheetRestingExtent(double screenHeight) =>
    screenHeight <= 0 ? 0.48 : (0.42 + 56 / screenHeight).clamp(0.42, 0.6);

/// The padding a camera fit uses on a screen with a card at its resting
/// height over the map: the route lands in the map above the card, clear of
/// the status bar and the control column at the right.
EdgeInsets cardFitPadding(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  final top = MediaQuery.paddingOf(context).top;
  return EdgeInsets.fromLTRB(
    40,
    top + 40,
    104,
    sheetRestingExtent(height) * height + 24,
  );
}

/// The scroll controller a sheet's content list uses, handed down by the
/// [DockingSheetShell] so the shell's scrollbar follows the list. A list
/// built outside a shell finds none and scrolls by itself.
class SheetContentScroll extends InheritedWidget {
  /// Creates the hand-down.
  const SheetContentScroll({
    required this.controller,
    required super.child,
    super.key,
  });

  /// The content's controller.
  final ScrollController controller;

  /// The controller the nearest shell hands down, or `null` without one.
  static ScrollController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SheetContentScroll>()
      ?.controller;

  @override
  bool updateShouldNotify(SheetContentScroll oldWidget) =>
      oldWidget.controller != controller;
}

/// The drag handle with its margins, [sheetHandleDp] tall.
///
/// Drawn by [DockingSheetShell] over the sheet's list, so it stays put and
/// fully visible while the list fades out under it. The list itself starts
/// with a spacer of the same height, so the handle is a drag on the list.
class SheetHandle extends StatelessWidget {
  /// Creates the handle.
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// The body of a [DraggableScrollableSheet] that morphs into the floating
/// navigation bar as it is pulled down.
///
/// The sheet is moved by its handle strip alone: [controller], the sheet's
/// own, drives a scrollable around the handle, so a drag there moves the
/// sheet up and down, snapping and docking as the sheet does, while the
/// content under it scrolls by itself at any height. It listens to the
/// sheet's notifications — dispatched from that scrollable, so a listener
/// here sees every drag, snap, `animateTo` and `jumpTo` — and paints a
/// [DockingSheetShell] for the current extent. [onDocked] is called when
/// the sheet crosses [sheetDockedThreshold] either way, from a notification,
/// never from a build; the screen owning the sheet resets it when the sheet
/// goes.
class DockingSheet extends StatefulWidget {
  /// Creates the sheet body.
  const DockingSheet({
    required this.controller,
    this.gripDp = sheetHandleDp,
    required this.initialExtent,
    required this.collapsedExtent,
    required this.dockedRange,
    required this.docks,
    required this.dockedBottomInset,
    required this.handle,
    required this.child,
    this.onDocked,
    this.onExtent,
    super.key,
  });

  /// The sheet's own scroll controller, from the sheet's builder; the handle
  /// strip is the scrollable it moves the sheet through.
  final ScrollController controller;

  /// How far down from the sheet's top a drag moves the sheet even over
  /// content that scrolls; see [DockingSheetShell.gripDp].
  final double gripDp;

  /// The sheet's `initialChildSize`, the extent until the first notification.
  final double initialExtent;

  /// The sheet's `minChildSize`, where it is fully docked.
  final double collapsedExtent;

  /// The travel above [collapsedExtent] the morph takes, as a fraction of the
  /// parent's height ([sheetDockingRangeDp] converted by the caller).
  final double dockedRange;

  /// Whether there is a bar to dock into. False while the bar is hidden: the
  /// sheet then keeps its full-width look down to its handle.
  final bool docks;

  /// What the bar covers at the bottom of the parent, in pixels: docked, the
  /// shell ends where the bar begins instead of running on behind it.
  final double dockedBottomInset;

  /// The handle strip, [sheetHandleDp] tall, above [child].
  final Widget handle;

  /// The content, scrolling on its own below the strip; nothing of it ever
  /// slides under the grip.
  final Widget child;

  /// Called when the sheet becomes docked or stops being docked.
  final ValueChanged<bool>? onDocked;

  /// Called with every extent the sheet reports, and once with
  /// [initialExtent] after the first frame, for the tab that comes next: its
  /// sheet starts where this one is.
  final ValueChanged<double>? onExtent;

  @override
  State<DockingSheet> createState() => _DockingSheetState();
}

class _DockingSheetState extends State<DockingSheet> {
  late double _extent = widget.initialExtent;
  bool _docked = false;

  @override
  void initState() {
    super.initState();
    // After the frame, not from it: the owner may rebuild its map for this.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExtent?.call(_extent);
    });
  }

  bool _onNotification(DraggableScrollableNotification notification) {
    if (notification.extent != _extent) {
      setState(() => _extent = notification.extent);
      widget.onExtent?.call(_extent);
    }
    final docked =
        DockingSheetShell.dockedFraction(
          extent: _extent,
          collapsedExtent: widget.collapsedExtent,
          dockedRange: widget.dockedRange,
          docks: widget.docks,
        ) >=
        sheetDockedThreshold;
    if (docked != _docked) {
      _docked = docked;
      widget.onDocked?.call(docked);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<DraggableScrollableNotification>(
        onNotification: _onNotification,
        child: DockingSheetShell(
          controller: widget.controller,
          gripDp: widget.gripDp,
          extent: _extent,
          collapsedExtent: widget.collapsedExtent,
          dockedRange: widget.dockedRange,
          docks: widget.docks,
          dockedBottomInset: widget.dockedBottomInset,
          handle: widget.handle,
          child: widget.child,
        ),
      );
}

/// The chrome of a bottom sheet at [extent] of its parent's height.
///
/// At rest it is the full-width sheet: no side margin, top corners of 28,
/// the surface colour, a hairline border and a shadow. Over the last
/// [dockedRange] of travel above [collapsedExtent] it becomes the navigation
/// bar's pill: 16 dp side margins, corners of 30, the bar's glass over a
/// blurred map, no shadow, its list faded out, and only the [handle] strip
/// left above a hairline where the bar begins. The sheet keeps reaching the
/// screen bottom until late in that travel; only then does its lower edge
/// lift to the bar's top, so it never floats before it docks. With [docks]
/// false there is no morph.
///
/// The [handle] strip is the sheet's grip: a scrollable driven by
/// [controller] whose only child is the strip, so a drag on it moves the
/// sheet and nothing else, and [child] keeps its own scrolling. The grip
/// reaches further than the strip, though: down to [gripDp], over the
/// content's title, a drag moves the sheet whatever the content does, and
/// content that has nothing to scroll is a grip all over, as a plain sheet
/// would be. Those drags are fed to the sheet's own scroll position, so the
/// sheet snaps, docks and reports exactly as it does for the strip.
class DockingSheetShell extends StatefulWidget {
  /// Creates the shell.
  const DockingSheetShell({
    required this.controller,
    this.gripDp = sheetHandleDp,
    required this.extent,
    required this.collapsedExtent,
    required this.dockedRange,
    required this.docks,
    required this.dockedBottomInset,
    required this.handle,
    required this.child,
    super.key,
  });

  /// The sheet's own scroll controller, attached to the handle strip.
  final ScrollController controller;

  /// How far down from the sheet's top a drag moves the sheet even over
  /// content that scrolls: the strip alone by default, or the strip and the
  /// content's title row for a sheet whose title has no buttons.
  final double gripDp;

  /// The sheet's current size, as a fraction of the parent's height.
  final double extent;

  /// The sheet's smallest size, where it is fully docked.
  final double collapsedExtent;

  /// The travel above [collapsedExtent] the morph takes, as a fraction.
  final double dockedRange;

  /// Whether there is a bar to dock into.
  final bool docks;

  /// What the bar covers at the bottom of the parent, in pixels.
  final double dockedBottomInset;

  /// The handle strip, drawn over [child] and never faded.
  final Widget handle;

  /// The content, scrolling on its own through the controller the shell
  /// hands down in [SheetContentScroll], so the shell's scrollbar can follow
  /// its list.
  final Widget child;

  /// How far a sheet at [extent] is into the morph: 0 at rest or above the
  /// morph range, 1 fully docked.
  static double dockedFraction({
    required double extent,
    required double collapsedExtent,
    required double dockedRange,
    required bool docks,
  }) {
    if (!docks || dockedRange <= 0) return 0;
    return (1 - (extent - collapsedExtent) / dockedRange).clamp(0.0, 1.0);
  }

  /// How far this shell is into the morph, 0 to 1.
  double get docked => dockedFraction(
    extent: extent,
    collapsedExtent: collapsedExtent,
    dockedRange: dockedRange,
    docks: docks,
  );

  @override
  State<DockingSheetShell> createState() => _DockingSheetShellState();
}

class _DockingSheetShellState extends State<DockingSheetShell> {
  /// Whether the content has more than fits: then its own scrolling takes
  /// a drag on it, and only the grip moves the sheet.
  bool _overflows = false;

  /// The content's scroll controller, handed down as the primary one so the
  /// content's list uses it and the scrollbar can follow that list.
  final ScrollController _content = ScrollController();

  /// The drag under way on the sheet's own scroll position, if any.
  Drag? _drag;

  bool _onMetrics(ScrollMetricsNotification notification) {
    final overflows = notification.metrics.maxScrollExtent > 0;
    if (overflows != _overflows) setState(() => _overflows = overflows);
    return false;
  }

  /// A drag that moves the sheet, handed to the sheet's own scroll position
  /// so it snaps and docks as a drag on the strip does.
  Map<Type, GestureRecognizerFactory> get _sheetDrag =>
      <Type, GestureRecognizerFactory>{
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              VerticalDragGestureRecognizer.new,
              (recognizer) {
                recognizer
                  ..onStart = (details) {
                    if (!widget.controller.hasClients) return;
                    _drag?.cancel();
                    _drag = widget.controller.position.drag(
                      details,
                      () => _drag = null,
                    );
                  }
                  ..onUpdate = (details) {
                    _drag?.update(details);
                  }
                  ..onEnd = (details) {
                    _drag?.end(details);
                    _drag = null;
                  }
                  ..onCancel = () {
                    _drag?.cancel();
                    _drag = null;
                  };
              },
            ),
      };

  @override
  void dispose() {
    _drag?.cancel();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final t = widget.docked;
    final controller = widget.controller;
    final handle = widget.handle;
    final dockedBottomInset = widget.dockedBottomInset;
    final gripDp = widget.gripDp;
    // Content that fits is a grip all over: its list has nothing to take
    // the drag, so the sheet does. On a platform that bounces, the list
    // would take it anyway, so such content is given clamping physics.
    Widget content = widget.child;
    if (!_overflows) {
      content = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context)
            .copyWith(physics: const ClampingScrollPhysics()),
        child: content,
      );
    }
    final margin = 16 * t;
    final radius = lerpDouble(28, dockedPillRadius, t)!;
    // The lower edge stays at the screen bottom for the first part of the
    // travel and lifts to the bar, easing in, over the rest, overlapping it
    // by a hair. Its bottom corners round off as the sheet narrows into a
    // pill and flatten again as the edge reaches the bar, where they are
    // the seam and a round corner would leave a notch beside the bar's
    // square top.
    final lift = t < 0.4 ? 0.0 : math.pow((t - 0.4) / 0.6, 2).toDouble();
    final topRadius = BorderRadius.vertical(
      top: Radius.circular(radius),
      bottom: Radius.circular(30 * t * (1 - lift)),
    );
    final bottom = math.max(0, dockedBottomInset - sheetDockedOverlapDp) * lift;
    // A hard clip at the seam: whatever the chrome or its layers might paint
    // below it, behind the bar, is cut, so the bar's rounded bottom stands
    // alone against the map.
    return ClipRect(
      clipper: _AboveSeamClipper(bottom),
      child: Padding(
        padding: EdgeInsets.fromLTRB(margin, 0, margin, bottom),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: topRadius,
            boxShadow: [
              if (t < 1)
                BoxShadow(
                  color: Color.fromARGB((0x40 * (1 - t)).round(), 0, 0, 0),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: topRadius,
            child: BackdropFilter(
              // No blur, on purpose: a blur over the map's native view makes
              // the engine composite the strip through an overlay whose
              // square bounds showed as dark corners beside the bar's round
              // ones. The glass colour alone reads the same; the filter
              // stays in the tree so the list keeps its state.
              enabled: false,
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(theme.colorScheme.surface, colors.glass, t),
                ),
                child: CustomPaint(
                  foregroundPainter: _ShellBorderPainter(
                    radius: radius,
                    color: colors.glassBorder,
                    hairline: t >= sheetDockedThreshold,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The docking fade; the list itself is the same
                        // widget every frame, so only its opacity changes.
                        // It starts below the strip, so a row scrolled to
                        // the top is in full view and takes its taps.
                        NotificationListener<ScrollMetricsNotification>(
                          onNotification: _onMetrics,
                          child: RawGestureDetector(
                            gestures: _sheetDrag,
                            // The thin bar at the right while the content
                            // scrolls, clear of the strip and the corner, so
                            // a card with more than fits says so; content
                            // that fits never shows one.
                            child: SheetContentScroll(
                              controller: _content,
                              child: RawScrollbar(
                                controller: _content,
                                thickness: 3,
                                radius: const Radius.circular(1.5),
                                thumbColor: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.45),
                                padding: const EdgeInsets.only(
                                  top: sheetHandleDp + 6,
                                  right: 3,
                                  bottom: 6,
                                ),
                                child: Opacity(
                                  opacity: 1 - t,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: sheetHandleDp,
                                    ),
                                    child: content,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // The grip below the strip, over the title: a drag
                        // there moves the sheet whatever the content does;
                        // a tap goes through to what is under it.
                        if (gripDp > sheetHandleDp)
                          Positioned(
                            top: sheetHandleDp,
                            left: 0,
                            right: 0,
                            height: gripDp - sheetHandleDp,
                            child: RawGestureDetector(
                              behavior: HitTestBehavior.translucent,
                              gestures: _sheetDrag,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: sheetHandleDp,
                          // The sheet's grip: the strip never scrolls
                          // itself, so every drag on it goes to the sheet,
                          // up or down, at any height, docked included.
                          child: SingleChildScrollView(
                            controller: controller,
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              width: double.infinity,
                              height: sheetHandleDp,
                              child: handle,
                            ),
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
    );
  }
}

/// Everything above the sheet's lower edge, which docked is the seam with
/// the bar.
class _AboveSeamClipper extends CustomClipper<Rect> {
  const _AboveSeamClipper(this.bottom);

  /// How far above the sheet's box the painted chrome ends.
  final double bottom;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width, size.height - bottom);

  @override
  bool shouldReclip(_AboveSeamClipper old) => old.bottom != bottom;
}

/// The hairline along the top and the sides of the shell, open at the
/// bottom, plus the short line under the handle once docked.
class _ShellBorderPainter extends CustomPainter {
  const _ShellBorderPainter({
    required this.radius,
    required this.color,
    required this.hairline,
  });

  final double radius;
  final Color color;
  final bool hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Half a pixel in, so the stroke lies inside the clip.
    const inset = 0.5;
    // The docked strip is shorter than its corner radius; the clip scales
    // the radius down to fit, and the stroke has to follow the same corner.
    final radius = math.min(this.radius, size.height);
    final r = radius - inset;
    final path = Path()
      ..moveTo(inset, size.height)
      ..lineTo(inset, radius)
      ..arcToPoint(Offset(radius, inset), radius: Radius.circular(r))
      ..lineTo(size.width - radius, inset)
      ..arcToPoint(
        Offset(size.width - inset, radius),
        radius: Radius.circular(r),
      )
      ..lineTo(size.width - inset, size.height);
    canvas.drawPath(path, paint);
    if (hairline) {
      // Just above the overlap with the bar, which is painted over it.
      final y = size.height - sheetDockedOverlapDp - inset;
      canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ShellBorderPainter old) =>
      old.radius != radius || old.color != color || old.hairline != hairline;
}
