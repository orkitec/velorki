import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// How tall the strip at the bottom of the screen is where the system's own
/// edge gesture starts: the swipe up to the home screen and the app
/// switcher. iOS hands the start of that touch to the app before it takes
/// it over, Android's gesture navigation has the same edge.
///
/// On iOS the home indicator's inset (34 points upright on a Face ID
/// iPhone, about 21 sideways, none with a home button); on Android the
/// system's bottom gesture inset (none with three-button navigation). Read
/// from the screen's own [media], above any scaffold that takes the bottom
/// padding off its body.
double systemGestureZoneHeight(MediaQueryData media, TargetPlatform platform) {
  final gestures = media.systemGestureInsets.bottom;
  return switch (platform) {
    TargetPlatform.iOS => math.max(media.viewPadding.bottom, gestures),
    _ => gestures,
  };
}

/// Keeps a touch that starts in the bottom [zone] of [child] from moving
/// anything in it: a sheet the system's swipe up would otherwise fling
/// open, the map it would pan. Such a touch reaches nothing in [child]
/// unless what it lands on is wrapped in a [GestureZonePassThrough] (the
/// rail where it reaches into the zone), which then gets it as usual. Nothing is drawn, and touches above the zone are
/// left alone.
class GestureZoneGuard extends SingleChildRenderObjectWidget {
  /// Creates the guard.
  const GestureZoneGuard({required this.zone, super.child, super.key});

  /// The height of the strip at the bottom, in logical pixels; 0 guards
  /// nothing.
  final double zone;

  @override
  RenderGestureZoneGuard createRenderObject(BuildContext context) =>
      RenderGestureZoneGuard(zone: zone);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGestureZoneGuard renderObject,
  ) {
    renderObject.zone = zone;
  }
}

/// The render object of [GestureZoneGuard].
class RenderGestureZoneGuard extends RenderProxyBox {
  /// Creates the render object.
  RenderGestureZoneGuard({required this.zone});

  /// The guarded strip's height. Only hit testing reads it, so a change
  /// needs no new layout or paint.
  double zone;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final inZone =
        zone > 0 &&
        size.contains(position) &&
        position.dy >= size.height - zone;
    if (!inZone) return super.hitTest(result, position: position);
    // What the touch would land on, asked first, without passing it on.
    final probe = BoxHitTestResult();
    super.hitTest(probe, position: position);
    if (probe.path.any((e) => e.target is _RenderGestureZonePassThrough)) {
      return super.hitTest(result, position: position);
    }
    // Taken here, and nothing here listens: the touch moves nothing.
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// Lets a touch in a [GestureZoneGuard]'s zone through to [child]: for
/// something there that is tapped, never dragged.
class GestureZonePassThrough extends SingleChildRenderObjectWidget {
  /// Wraps [child].
  const GestureZonePassThrough({super.child, super.key});

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderGestureZonePassThrough();
}

class _RenderGestureZonePassThrough extends RenderProxyBox {}

/// A [MaterialApp.builder] that guards the system gesture zone of the whole
/// app, the root navigator's modal sheets included: they are routes above
/// the shell, outside the guard it wraps its own body in.
Widget gestureZoneAppBuilder(BuildContext context, Widget? child) =>
    GestureZoneGuard(
      zone: systemGestureZoneHeight(
        MediaQuery.of(context),
        defaultTargetPlatform,
      ),
      child: child,
    );
