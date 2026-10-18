import 'dart:ui' show ImageFilter;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../app/theme.dart' show BarStyle;

/// How far the glass in [style] blurs what is behind it, as a standard
/// deviation in logical pixels; `null` for a style without blur.
///
/// [BarStyle.clear] blurs harder than [BarStyle.subtle]; it is clearer for
/// its thinner glass, not a weaker blur.
double? glassBlurSigma(BarStyle style) => switch (style) {
  BarStyle.solid || BarStyle.transparent => null,
  BarStyle.subtle => 8,
  BarStyle.clear => 4,
};

/// The blur behind one piece of glass: the floating bar, a panel over the
/// map, a chip, the docked pill. One widget for all of them, so the glass
/// is blurred the same way everywhere.
///
/// On the phone it is a [BackdropFilter] and nothing more. In a browser the
/// map is an HTML element under Flutter's canvas, which a [BackdropFilter]
/// cannot reach; there the piece of glass is also reported to the page
/// ([GlassBackdrop.tracked]), which blurs the map behind it with the
/// browser's own `backdrop-filter` (`app/web/web_glass_layer.dart`).
class GlassBackdrop extends StatelessWidget {
  /// Blurs behind [child] in [style], clipped to [borderRadius] (a stadium
  /// with [stadium]); nothing while not [enabled].
  const GlassBackdrop({
    required this.style,
    required this.child,
    this.enabled = true,
    this.grouped = false,
    this.borderRadius = BorderRadius.zero,
    this.stadium = false,
    super.key,
  });

  /// The glass style, which sets the blur.
  final BarStyle style;

  /// Whether to blur at all.
  final bool enabled;

  /// Whether the blur reads the app's shared backdrop
  /// ([BackdropFilter.grouped]).
  final bool grouped;

  /// The shape of the glass, for the browser's blur; the widget itself
  /// clips nothing, its parent does.
  final BorderRadius borderRadius;

  /// Whether the shape is a stadium, its corners half its height.
  final bool stadium;

  /// The glass.
  final Widget child;

  /// Whether pieces of glass report themselves for the browser's blur: set
  /// by the browser's bootstrap only, so the phone's tree is the
  /// [BackdropFilter] alone.
  static bool tracked = false;

  @override
  Widget build(BuildContext context) {
    final sigma = glassBlurSigma(style);
    final on = enabled && sigma != null;
    final filter = ImageFilter.blur(sigmaX: sigma ?? 0, sigmaY: sigma ?? 0);
    final blur = grouped
        ? BackdropFilter.grouped(enabled: on, filter: filter, child: child)
        : BackdropFilter(enabled: on, filter: filter, child: child);
    if (!tracked) return blur;
    return _GlassMarker(
      sigma: on ? sigma : null,
      borderRadius: borderRadius,
      stadium: stadium,
      child: blur,
    );
  }
}

/// A piece of glass as the page sees it: where it is in the window, its
/// shape, how strongly it blurs and how much of it shows.
@immutable
class GlassRect {
  /// Creates the description.
  const GlassRect({
    required this.rect,
    required this.radius,
    required this.sigma,
    required this.opacity,
  });

  /// Where the glass is, in logical pixels of the window, already cut by
  /// whatever clips it.
  final Rect rect;

  /// Its corner radius.
  final double radius;

  /// Its blur.
  final double sigma;

  /// How much of it shows, from the fades above it.
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is GlassRect &&
      other.rect == rect &&
      other.radius == radius &&
      other.sigma == sigma &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(rect, radius, sigma, opacity);

  @override
  String toString() => 'GlassRect($rect, r $radius, σ $sigma, α $opacity)';
}

/// The pieces of glass on screen now, for the browser's blur: those that
/// are painted, cut by their clips, with the opacity of the fades above
/// them. Empty unless [GlassBackdrop.tracked].
List<GlassRect> visibleGlass() => <GlassRect>[
  for (final marker in _RenderGlassMarker._attached) ?marker._visible(),
];

class _GlassMarker extends SingleChildRenderObjectWidget {
  const _GlassMarker({
    required this.sigma,
    required this.borderRadius,
    required this.stadium,
    required super.child,
  });

  final double? sigma;
  final BorderRadius borderRadius;
  final bool stadium;

  @override
  _RenderGlassMarker createRenderObject(BuildContext context) =>
      _RenderGlassMarker()
        ..sigma = sigma
        ..borderRadius = borderRadius
        ..stadium = stadium;

  @override
  void updateRenderObject(BuildContext context, _RenderGlassMarker r) => r
    ..sigma = sigma
    ..borderRadius = borderRadius
    ..stadium = stadium;
}

class _RenderGlassMarker extends RenderProxyBox {
  static final Set<_RenderGlassMarker> _attached = <_RenderGlassMarker>{};

  double? sigma;
  BorderRadius borderRadius = BorderRadius.zero;
  bool stadium = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _attached.add(this);
  }

  @override
  void detach() {
    _attached.remove(this);
    super.detach();
  }

  /// This glass as the page should blur it, or `null` when it blurs
  /// nothing or does not show: not laid out, not painted by an ancestor
  /// (an offstage route or tab, a fade at zero), or clipped away.
  GlassRect? _visible() {
    final sigma = this.sigma;
    if (sigma == null || !hasSize || size.isEmpty) return null;
    final chain = <RenderObject>[];
    for (RenderObject? node = this; node != null; node = node.parent) {
      chain.add(node);
    }
    // Down from the top, the transform from each node's coordinates to the
    // window's, each clip in the window's and the opacity on the way.
    var transform = Matrix4.identity();
    var clip = Rect.largest;
    var opacity = 1.0;
    for (var i = chain.length - 1; i > 0; i--) {
      final parent = chain[i];
      final child = chain[i - 1];
      if (!parent.paintsChild(child)) return null;
      if (parent is RenderOpacity) opacity *= parent.opacity;
      if (parent is RenderAnimatedOpacityMixin) {
        opacity *= parent.opacity.value;
      }
      final parentClip = parent.describeApproximatePaintClip(child);
      if (parentClip != null && i < chain.length - 1) {
        clip = clip.intersect(MatrixUtils.transformRect(transform, parentClip));
      }
      // The root view's own transform is the device's pixels: left out, so
      // the result is in the window's logical pixels.
      if (i < chain.length - 1) parent.applyPaintTransform(child, transform);
    }
    if (opacity <= 0) return null;
    final rect = MatrixUtils.transformRect(
      transform,
      Offset.zero & size,
    ).intersect(clip);
    if (rect.isEmpty || rect.width <= 0 || rect.height <= 0) return null;
    final radius = stadium ? size.shortestSide / 2 : borderRadius.topLeft.x;
    return GlassRect(
      rect: rect,
      radius: radius,
      sigma: sigma,
      opacity: opacity.clamp(0.0, 1.0),
    );
  }
}
