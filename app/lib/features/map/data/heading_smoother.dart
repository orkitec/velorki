import 'geojson.dart';

/// Ground speed at which the heading cone appears.
///
/// Deliberately above [minHeadingSpeedMps]: a single threshold makes the cone
/// blink on and off while the rider rolls out at walking pace.
const double headingConeOnSpeedMps = 1.5;

/// Ground speed below which a visible heading cone disappears again.
const double headingConeOffSpeedMps = 0.6;

/// Weight of the newest course in the circular exponential average while the
/// rider is clearly riding.
///
/// A course measured at riding speed is a good one, so the cone may follow it
/// closely and be through a turn in two or three fixes.
const double headingAlphaFast = 0.5;

/// The same at a slower pace, where the course is half noise and the average
/// has to work harder to keep the cone still.
const double headingAlphaSlow = 0.3;

/// Ground speed from which [headingAlphaFast] is used.
const double headingAlphaFastSpeedMps = 4;

/// [previous] moved [weight] of the way towards [next], the short way around
/// the circle, so 359° and 1° average to 0° and not to 180°.
///
/// Shared with the compass, which averages its samples the same way.
double blendHeadings(double previous, double next, double weight) {
  final delta = ((next - previous + 540) % 360) - 180;
  final blended = (previous + weight * delta) % 360;
  return blended < 0 ? blended + 360 : blended;
}

/// The angle between two headings, 0 to 180 degrees.
double headingDifference(double a, double b) {
  final delta = ((a - b) % 360 + 360) % 360;
  return delta > 180 ? 360 - delta : delta;
}

/// Turns the raw course of a fix into the heading the puck's cone is drawn at.
///
/// Two problems, one object: a plain speed threshold blinks the cone on and
/// off around walking pace, and the raw course jitters by tens of degrees
/// between fixes. So visibility has hysteresis ([onSpeedMps] to show,
/// [offSpeedMps] to hide) and the angle is an exponential average taken the
/// long way around the circle, so 359° and 1° average to 0° and not to 180°.
///
/// A heading from the phone's compass is a different animal and says so
/// ([update]'s `fromCompass`): it is where the phone points rather than where
/// the rider has been, so it means something at a standstill and shows the
/// cone at any speed. Both kinds go through the same average, so handing over
/// from one to the other turns the cone rather than jumping it.
///
/// Pure Dart with no map types in sight: one instance lives per map adapter
/// and is fed every fix.
class HeadingSmoother {
  /// Creates a smoother with the production thresholds.
  ///
  /// A given [alpha] is used at every speed; leaving it out picks one per fix,
  /// which is what production wants.
  HeadingSmoother({
    this.onSpeedMps = headingConeOnSpeedMps,
    this.offSpeedMps = headingConeOffSpeedMps,
    this.alpha,
  });

  /// Ground speed at or above which a hidden cone appears.
  final double onSpeedMps;

  /// Ground speed below which a visible cone hides again.
  final double offSpeedMps;

  /// Weight of the newest course, between 0 and 1, or `null` to let the speed
  /// of each fix decide.
  final double? alpha;

  /// The weight this fix's course is blended in with.
  double alphaAt(double? speedMps) =>
      alpha ??
      ((speedMps ?? 0) >= headingAlphaFastSpeedMps
          ? headingAlphaFast
          : headingAlphaSlow);

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
  ///
  /// [fromCompass] marks [headingDeg] as a compass heading instead of a
  /// course over ground. That one is worth drawing however slowly the rider
  /// is going, so it brings the cone up and keeps it up; a course still has
  /// to earn its place with speed.
  double? update({
    double? headingDeg,
    double? speedMps,
    bool fromCompass = false,
  }) {
    final speed = speedMps != null && speedMps.isFinite ? speedMps : 0.0;
    final course = fromCompass
        ? normalizedHeading(headingDeg)
        : puckHeading(headingDeg, speedMps);
    if (fromCompass && course != null) {
      // Where the phone points is true standing still, so the speed rules do
      // not apply to it at all.
      _visible = true;
    } else if (_visible) {
      if (speed < offSpeedMps) {
        reset();
        return null;
      }
    } else if (speed >= onSpeedMps) {
      _visible = true;
    } else {
      return null;
    }

    if (course != null) {
      final previous = _heading;
      // The same average either way, so a compass heading handing over to a
      // course (or back) turns the cone instead of snapping it.
      _heading = previous == null
          ? course
          : blendHeadings(previous, course, alphaAt(speedMps));
    }
    return _heading;
  }

  /// Hides the cone and forgets the average, so the next one starts from the
  /// first course it sees instead of drifting there.
  void reset() {
    _visible = false;
    _heading = null;
  }
}
