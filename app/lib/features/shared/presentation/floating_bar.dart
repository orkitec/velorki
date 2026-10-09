import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/shell_layout.dart';
import '../../../app/theme.dart';
import 'docking_sheet.dart' show dockedPillRadius;
import 'gesture_zone_guard.dart';

/// The height of the floating bar's glass: the tab bar's, and the figures
/// bar's that takes its place during a ride.
const double floatingBarHeight = 72;

/// The air under the floating bar, above the safe area, where the system's
/// gesture zone is: the map's attribution chip sits in that zone under the
/// bar. Turned sideways, the air beside the rail.
const double floatingBarBottomGap = 12;

/// How much higher the bar stands upright on a phone with no gesture zone at
/// the bottom (an iPhone with a home button, Android's three-button
/// navigation): a band under it for the map's attribution chip, which would
/// otherwise have nowhere under the bar to go. The chip is about 21 dp tall
/// and stands 6 above the safe area; this leaves some air above it.
const double attributionBandHeight = 26;

/// The air under the upright floating bar on the screen [media] describes
/// (the screen's own metrics: its safe area and gesture insets), above the
/// safe area: [floatingBarBottomGap], and [attributionBandHeight] more
/// where there is no system gesture zone at the bottom. The one source for
/// everything that stands on the bar or measures it: the tab bar, the
/// figures bar, the sheets docked into them and the map's attribution.
double floatingBarBottomGapFor(MediaQueryData media, TargetPlatform platform) =>
    floatingBarBottomGap +
    (barRaisedForAttribution(media, platform) ? attributionBandHeight : 0);

/// Whether the upright bar stands [attributionBandHeight] higher on the
/// screen [media] describes, with the map's attribution chip under it on
/// the safe area's edge: where the system has no gesture zone at the bottom.
bool barRaisedForAttribution(MediaQueryData media, TargetPlatform platform) =>
    systemGestureZoneHeight(media, platform) == 0;

/// [floatingBarBottomGapFor] the screen at [context], upright, depending on
/// its safe area and gesture insets only.
double floatingBarBottomGapOf(BuildContext context) => floatingBarBottomGapFor(
  MediaQueryData(
    viewPadding: MediaQuery.viewPaddingOf(context),
    systemGestureInsets: MediaQuery.systemGestureInsetsOf(context),
  ),
  defaultTargetPlatform,
);

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
/// a sheet docked into the bar is the same glass as the bar, and so does
/// the chrome over the map (`GlassPanel`, the bike chips), in [glassTint].
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
  /// [BarStyle.clear] without one, and [BarStyle.solid] whenever the
  /// system asks for more contrast, whatever was picked.
  static BarStyle of(BuildContext context) {
    if (MediaQuery.maybeHighContrastOf(context) ?? false) {
      return BarStyle.solid;
    }
    return context
            .dependOnInheritedWidgetOfExactType<FloatingBarStyle>()
            ?.style ??
        BarStyle.clear;
  }

  @override
  bool updateShouldNotify(FloatingBarStyle oldWidget) =>
      oldWidget.style != style;
}

/// The tint laid over the blur in [style], for the bar and the controls over
/// the map alike: the glass styles take a fraction of the theme's bar fill,
/// solid and transparent all of it.
Color glassTint(VelorkiColors colors, BarStyle style) {
  // The bar and the controls are one material in every style: a difference
  // in tint side by side over the map read as two kinds of glass. On iOS the
  // system's own blur frosts the map first, so its tint is the thinnest;
  // elsewhere the engine's plain blur has no frost, so a touch more.
  final base = colors.barFill(style);
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  return switch (style) {
    BarStyle.clear => base.withValues(alpha: ios ? 0.18 : 0.24),
    BarStyle.subtle => base.withValues(alpha: ios ? 0.30 : 0.36),
    BarStyle.solid || BarStyle.transparent => base,
  };
}

/// What the bar, and the chrome over the map, blur their backdrop with in
/// [style]; `null` for none.
///
/// [BarStyle.clear] blurs harder than [BarStyle.subtle]; it is clearer for
/// its thinner glass, not a weaker blur. A blur only: over the map's native
/// view iOS applies a plain blur, and a blur composed with a colour filter
/// (it once lifted the saturation) came out barely blurred at all.
ImageFilter? floatingBarFilter(BarStyle style) => switch (style) {
  BarStyle.solid || BarStyle.transparent => null,
  BarStyle.subtle => ImageFilter.blur(sigmaX: 8, sigmaY: 8),
  BarStyle.clear => ImageFilter.blur(sigmaX: 4, sigmaY: 4),
};

/// The glass pill a bar floats in at the bottom of the screen: the tab bar,
/// and the figures bar Record's sheet folds into during a ride, so the two
/// sit in exactly the same place with exactly the same shape.
///
/// [floatingBarSideMargin] from the sides, [floatingBarBottomGapFor] above
/// the safe area, corners of 30 and a shadow at rest. [docked], a sheet's strip
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
    final fill = glassTint(colors, style);
    final filter = floatingBarFilter(style);
    // Docked, the bar paints its own shape — square top, round bottom —
    // and clips nothing: over the map's native view a rounded clip with
    // straight top corners is not applied, and the glass came out square at
    // the bottom with its round border drawn inside. A rect clip and a
    // painted shape need no such favour from the compositor.
    final radius = docked ? BorderRadius.zero : BorderRadius.circular(30);
    // Turned sideways the shell is the rail, its air the plain gap.
    final gap = ShellLayout.of(context).sideRail
        ? floatingBarBottomGap
        : floatingBarBottomGapOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        floatingBarSideMargin,
        0,
        floatingBarSideMargin,
        MediaQuery.viewPaddingOf(context).bottom + gap,
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
                    // Outside the bar only, as under the controls' glass.
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 24,
                      blurStyle: BlurStyle.outer,
                    ),
                  ],
          ),
          // At rest a rounded clip with four equal corners, which iOS
          // clips a blur over the map to. Docked, no blur of its own: the
          // sheet blurs strip and bar as one pill, and the bar paints its
          // glass in its shape (BarGlassDecoration).
          // Not in the app's backdrop group: at rest the bar lies over the
          // tab's card, which is painted after the group reads the map, so a
          // shared backdrop showed the map through the card.
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              enabled: filter != null && !docked,
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
                        rim: null,
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
