import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'docking_sheet.dart' show dockedPillRadius;

/// The height of the floating bar's glass: the tab bar's, and the figures
/// bar's that takes its place during a ride.
const double floatingBarHeight = 72;

/// The air under the floating bar, above the safe area.
const double floatingBarBottomGap = 12;

/// The side margin of the floating bar.
const double floatingBarSideMargin = 16;

/// The glass pill a bar floats in at the bottom of the screen: the tab bar,
/// and the figures bar Record's sheet folds into during a ride, so the two
/// sit in exactly the same place with exactly the same shape.
///
/// [floatingBarSideMargin] from the sides, [floatingBarBottomGap] above the
/// safe area, corners of 30 and a shadow at rest. [docked], a sheet's strip
/// rests on its top edge: the top goes square and open, the seam being the
/// strip's own hairline, and the shadow and blur go (see below). [child] is
/// [floatingBarHeight] tall.
class FloatingBarShell extends StatelessWidget {
  /// Creates the shell.
  const FloatingBarShell({required this.child, this.docked = false, super.key});

  /// Whether a sheet rests on the bar's top edge.
  final bool docked;

  /// What the bar holds.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).velorki;
    // Docked, the bar paints its own shape — square top, round bottom —
    // and clips nothing: over the map's native view a rounded clip with
    // straight top corners is not applied, and the glass came out square at
    // the bottom with its round border drawn inside. A rect clip and a
    // painted shape need no such favour from the compositor.
    final radius = docked ? BorderRadius.zero : BorderRadius.circular(30);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        floatingBarSideMargin,
        0,
        floatingBarSideMargin,
        MediaQuery.viewPaddingOf(context).bottom + floatingBarBottomGap,
      ),
      // Docked there is no shadow to keep off the sheet, but the clip stays
      // in the tree either way so the bar keeps its state.
      child: ClipRect(
        clipper: _BarShadowClipper(cutTop: docked),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            // No shadow at all while docked: beside the seam it would show
            // as dark wedges under the sheet's strip.
            boxShadow: docked
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              // Over the map's native view the blur is applied by the
              // engine to a rectangle, not to this rounded clip; at rest the
              // shadow hides its square corners, docked there is no shadow
              // and they showed as half circles beside the round ones. So
              // docked, the glass colour alone.
              enabled: !docked,
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: docked
                    ? _BarBorder(
                        color: colors.glassBorder,
                        docked: true,
                        fill: colors.glass,
                      )
                    : BoxDecoration(color: colors.glass),
                // Painted rather than a Border: a rounded border cannot
                // leave one side out, and docked the top edge is the seam.
                foregroundDecoration: docked
                    ? null
                    : _BarBorder(color: colors.glassBorder, docked: false),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hairline around the bar's pill; docked, it is open at the top, where
/// the sheet's strip continues it.
class _BarBorder extends Decoration {
  const _BarBorder({required this.color, required this.docked, this.fill});

  /// The glass to fill the docked shape with, under the hairline; `null`
  /// paints the hairline alone.
  final Color? fill;

  final Color color;
  final bool docked;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _BarBorderPainter(this);
}

class _BarBorderPainter extends BoxPainter {
  _BarBorderPainter(this.border);

  final _BarBorder border;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final paint = Paint()
      ..color = border.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Half a pixel in, so the stroke lies inside the clip.
    final rect = (offset & size).deflate(0.5);
    if (!border.docked) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(29.5)),
        paint,
      );
      return;
    }
    final fill = border.fill;
    if (fill != null) {
      final box = offset & size;
      final shape = Path()
        ..moveTo(box.left, box.top)
        ..lineTo(box.right, box.top)
        ..lineTo(box.right, box.bottom - dockedPillRadius)
        // Round the right way: this path runs down the right side and back
        // along the bottom, so its convex corners are clockwise arcs on a
        // screen whose y points down (the border below runs the other way).
        ..arcToPoint(
          Offset(box.right - dockedPillRadius, box.bottom),
          radius: const Radius.circular(dockedPillRadius),
        )
        ..lineTo(box.left + dockedPillRadius, box.bottom)
        ..arcToPoint(
          Offset(box.left, box.bottom - dockedPillRadius),
          radius: const Radius.circular(dockedPillRadius),
        )
        ..close();
      canvas.drawPath(shape, Paint()..color = fill);
    }
    const r = Radius.circular(dockedPillRadius - 0.5);
    final path = Path()
      ..moveTo(rect.left, rect.top - 0.5)
      ..lineTo(rect.left, rect.bottom - (dockedPillRadius - 0.5))
      // Down the left side and along the bottom: both corners are convex,
      // which on a screen is an arc drawn against the clock.
      ..arcToPoint(
        Offset(rect.left + (dockedPillRadius - 0.5), rect.bottom),
        radius: r,
        clockwise: false,
      )
      ..lineTo(rect.right - (dockedPillRadius - 0.5), rect.bottom)
      ..arcToPoint(
        Offset(rect.right, rect.bottom - (dockedPillRadius - 0.5)),
        radius: r,
        clockwise: false,
      )
      ..lineTo(rect.right, rect.top - 0.5);
    canvas.drawPath(path, paint);
  }
}

/// Lets the bar's shadow out on every side but, while docked, the top.
class _BarShadowClipper extends CustomClipper<Rect> {
  const _BarShadowClipper({required this.cutTop});

  final bool cutTop;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -100,
    cutTop ? 0 : -100,
    size.width + 100,
    size.height + 100,
  );

  @override
  bool shouldReclip(_BarShadowClipper old) => old.cutTop != cutTop;
}
