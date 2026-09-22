import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// The height of a sheet's handle strip: the drag handle with its margins.
const double sheetHandleDp = 28;

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
/// It listens to the sheet's own notifications — they are dispatched from
/// the scrollable inside [child], so a listener here sees every drag, snap,
/// `animateTo` and `jumpTo` — and paints a [DockingSheetShell] for the
/// current extent. [onDocked] is called when the sheet crosses
/// [sheetDockedThreshold] either way, from a notification, never from a
/// build; the screen owning the sheet resets it when the sheet goes.
class DockingSheet extends StatefulWidget {
  /// Creates the sheet body.
  const DockingSheet({
    required this.initialExtent,
    required this.collapsedExtent,
    required this.dockedRange,
    required this.docks,
    required this.dockedBottomInset,
    required this.handle,
    required this.child,
    this.onDocked,
    this.onExtent,
    this.contentOpacity = kAlwaysCompleteAnimation,
    super.key,
  });

  /// The opacity of [child] on top of the docking fade: the list dissolves
  /// around a tab change while the frame stays.
  final Animation<double> contentOpacity;

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

  /// The handle strip, [sheetHandleDp] tall, drawn over [child].
  final Widget handle;

  /// The sheet's scrollable, starting with a [sheetHandleDp] spacer.
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
          extent: _extent,
          collapsedExtent: widget.collapsedExtent,
          dockedRange: widget.dockedRange,
          docks: widget.docks,
          dockedBottomInset: widget.dockedBottomInset,
          handle: widget.handle,
          contentOpacity: widget.contentOpacity,
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
class DockingSheetShell extends StatelessWidget {
  /// Creates the shell.
  const DockingSheetShell({
    required this.extent,
    required this.collapsedExtent,
    required this.dockedRange,
    required this.docks,
    required this.dockedBottomInset,
    required this.handle,
    required this.child,
    this.contentOpacity = kAlwaysCompleteAnimation,
    super.key,
  });

  /// The opacity of [child] on top of the docking fade.
  final Animation<double> contentOpacity;

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

  /// The sheet's scrollable.
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final t = docked;
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
                        // The docking fade and the tab change's content fade,
                        // composed; the list itself is the same widget every
                        // frame, so only its opacity changes.
                        AnimatedBuilder(
                          animation: contentOpacity,
                          builder: (context, _) => Opacity(
                            opacity: (1 - t) * contentOpacity.value,
                            child: child,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          // A drag on the handle is a drag on the list under
                          // it, which is what moves the sheet.
                          child: IgnorePointer(child: handle),
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
