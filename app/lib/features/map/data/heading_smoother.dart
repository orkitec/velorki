import 'geojson.dart';

/// Ground speed at which the heading cone appears.
///
/// Deliberately above [minHeadingSpeedMps]: a single threshold makes the cone
/// blink on and off while the rider rolls out at walking pace.
const double headingConeOnSpeedMps = 1.5;

/// Ground speed below which a visible heading cone disappears again.
const double headingConeOffSpeedMps = 0.6;

/// Weight of the newest course in the circular exponential average.
///
/// Low enough to swallow the jitter of a consumer GNSS course, high enough
/// that the cone has caught up with a turn within a few fixes.
const double headingSmoothingAlpha = 0.35;

/// Turns the raw course of a fix into the heading the puck's cone is drawn at.
///
/// Two problems, one object: a plain speed threshold blinks the cone on and
/// off around walking pace, and the raw course jitters by tens of degrees
/// between fixes. So visibility has hysteresis ([onSpeedMps] to show,
/// [offSpeedMps] to hide) and the angle is an exponential average taken the
/// long way around the circle, so 359° and 1° average to 0° and not to 180°.
///
/// Pure Dart with no map types in sight: one instance lives per map adapter
/// and is fed every fix.
class HeadingSmoother {
  /// Creates a smoother with the production thresholds.
  HeadingSmoother({
    this.onSpeedMps = headingConeOnSpeedMps,
    this.offSpeedMps = headingConeOffSpeedMps,
    this.alpha = headingSmoothingAlpha,
  });

  /// Ground speed at or above which a hidden cone appears.
  final double onSpeedMps;

  /// Ground speed below which a visible cone hides again.
  final double offSpeedMps;

  /// Weight of the newest course, between 0 and 1.
  final double alpha;

  bool _visible = false;
  double? _heading;

  /// Whether the cone is currently shown.
  bool get isVisible => _visible;

  /// The smoothed course in degrees, or `null` while the cone is hidden or no
  /// usable course has arrived yet.
  double? get heading => _visible ? _heading : null;

  /// Feeds one fix and returns the heading to draw, `null` for no cone.
  ///
  /// A fix whose course is unusable — absent, broken, or too slow to mean
  /// anything, as [puckHeading] decides — keeps the last smoothed heading for
  /// as long as the cone stays visible, rather than dropping the cone for one
  /// frame.
  double? update({double? headingDeg, double? speedMps}) {
    final speed = speedMps != null && speedMps.isFinite ? speedMps : 0.0;
    if (_visible) {
      if (speed < offSpeedMps) {
        reset();
        return null;
      }
    } else if (speed >= onSpeedMps) {
      _visible = true;
    } else {
      return null;
    }

    final course = puckHeading(headingDeg, speedMps);
    if (course != null) {
      final previous = _heading;
      _heading = previous == null ? course : _blend(previous, course);
    }
    return _heading;
  }

  /// Hides the cone and forgets the average, so the next one starts from the
  /// first course it sees instead of drifting there.
  void reset() {
    _visible = false;
    _heading = null;
  }

  /// [previous] moved [alpha] of the way towards [course], the short way
  /// around the circle.
  double _blend(double previous, double course) {
    final delta = ((course - previous + 540) % 360) - 180;
    final blended = (previous + alpha * delta) % 360;
    return blended < 0 ? blended + 360 : blended;
  }
}
