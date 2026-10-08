import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../app/shell_layout.dart';
import '../../../app/theme.dart';
import 'docking_sheet.dart' show dockedPillRadius;

/// The height of the floating bar's glass: the tab bar's, and the figures
/// bar's that takes its place during a ride.
const double floatingBarHeight = 72;

/// The air under the floating bar, above the safe area.
const double floatingBarBottomGap = 12;

/// The side margin of the floating bar.
const double floatingBarSideMargin = 16;

/// The width of the rail the bar becomes on a phone turned sideways: the
/// bar itself, turned a quarter.
const double floatingRailWidth = floatingBarHeight;

/// How much of the screen's [side] the rail takes, from the edge to its
/// inner side: the safe area, the air and the rail itself, as the bar takes
/// the safe area, the air and itself at the bottom.
double floatingRailInset(EdgeInsets viewPadding, RailSide side) =>
    (side == RailSide.left ? viewPadding.left : viewPadding.right) +
    floatingBarBottomGap +
    floatingRailWidth;

/// The [BarStyle] the floating bars under it take: the shell's, from the
/// rider's choice in Settings → Appearance. The tab sheets read it too, so
/// a sheet docked into the bar is the same glass as the bar.
class FloatingBarStyle extends InheritedWidget {
  /// Hands [style] down to [child].
  const FloatingBarStyle({
    required this.style,
    required super.child,
    super.key,
  });

  /// The rider's choice.
  final BarStyle style;

  /// The style a bar at [context] is drawn in: the nearest scope's,
  /// [BarStyle.subtle] without one, and [BarStyle.solid] whenever the
  /// system asks for more contrast, whatever was picked.
  static BarStyle of(BuildContext context) {
    if (MediaQuery.maybeHighContrastOf(context) ?? false) {
      return BarStyle.solid;
    }
    return context
            .dependOnInheritedWidgetOfExactType<FloatingBarStyle>()
            ?.style ??
        BarStyle.subtle;
  }

  @override
  bool updateShouldNotify(FloatingBarStyle oldWidget) =>
      oldWidget.style != style;
}

/// How much [BarStyle.clear] lifts the colours behind the bar.
const double clearBarSaturation = 1.7;

/// What the bar blurs its backdrop with in [style]; `null` for none.
///
/// [BarStyle.clear] blurs harder than [BarStyle.subtle] and lifts the
/// saturation of what is behind, so the map shows through as colour rather
/// than as a grey haze.
ImageFilter? floatingBarFilter(BarStyle style) => switch (style) {
  BarStyle.solid || BarStyle.transparent => null,
  BarStyle.subtle => ImageFilter.blur(sigmaX: 18, sigmaY: 18),
  BarStyle.clear => ImageFilter.compose(
    outer: ColorFilter.matrix(saturationMatrix(clearBarSaturation)),
    inner: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
  ),
};

/// The colour matrix that scales saturation by [s], about the Rec. 709
/// luminance, so a grey stays the same grey.
List<double> saturationMatrix(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final k = 1 - s;
  return <double>[
    r * k + s, g * k, b * k, 0, 0, //
    r * k, g * k + s, b * k, 0, 0, //
    r * k, g * k, b * k + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// The glass pill a bar floats in at the bottom of the screen: the tab bar,
/// and the figures bar Record's sheet folds into during a ride, so the two
/// sit in exactly the same place with exactly the same shape.
///
/// [floatingBarSideMargin] from the sides, [floatingBarBottomGap] above the
/// safe area, corners of 30 and a shadow at rest. [docked], a sheet's strip
/// rests on its top edge: the top goes square and open, the seam being the
/// strip's own hairline, and the shadow and blur go (see below). [child] is
/// [floatingBarHeight] tall. How see-through the glass is follows
/// [FloatingBarStyle].
///
/// On a phone turned sideways the shell is built inside a
/// `QuarterTurnedFrame`, so the same pill stands as a rail on the side the
/// phone's bottom edge went to.
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
    final style = FloatingBarStyle.of(context);
    final fill = colors.barFill(style);
    final filter = floatingBarFilter(style);
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
              // shadow hides its square corners. Docked, behind the bar is
              // the map too, and iOS draws no blur there at all, whatever
              // the clip (tried with one of four equal corners reaching past
              // the top): so docked, the style's glass colour alone, see-
              // through as much as at rest but unblurred.
              enabled: !docked && filter != null,
              filter: filter ?? ImageFilter.blur(),
              child: Container(
                decoration: docked
                    ? BarGlassDecoration(
                        color: colors.glassBorder,
                        docked: true,
                        fill: fill,
                      )
                    : BoxDecoration(color: fill),
                // Painted rather than a Border: a rounded border cannot
                // leave one side out, and docked the top edge is the seam.
                foregroundDecoration: docked
                    ? null
                    : BarGlassDecoration(
                        color: colors.glassBorder,
                        docked: false,
                        rim: style == BarStyle.clear ? colors.barRim : null,
                      ),
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
/// the sheet's strip continues it, and fills the docked shape with the glass.
class BarGlassDecoration extends Decoration {
  /// Creates the decoration.
  const BarGlassDecoration({
    required this.color,
    required this.docked,
    this.fill,
    this.rim,
  });

  /// The light rim along the top edge at rest, fading out by the middle;
  /// `null` for none.
  final Color? rim;

  /// The glass to fill the docked shape with, under the hairline; `null`
  /// paints the hairline alone.
  final Color? fill;

  /// The hairline's colour.
  final Color color;

  /// Whether the bar is docked: square top, open at the seam.
  final bool docked;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _BarGlassPainter(this);
}

class _BarGlassPainter extends BoxPainter {
  _BarGlassPainter(this.border);

  final BarGlassDecoration border;

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
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(29.5));
      canvas.drawRRect(rrect, paint);
      final rim = border.rim;
      if (rim != null) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[rim, rim.withValues(alpha: 0)],
              stops: const <double>[0, 0.5],
            ).createShader(rect),
        );
      }
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
