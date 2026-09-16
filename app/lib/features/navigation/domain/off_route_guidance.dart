import 'package:velorki_geo/velorki_geo.dart';

/// Where a ride stands in relation to the route it was planned along.
enum OffRouteState {
  /// On the route, or near enough to it: the plan's own turns are being
  /// given.
  onRoute,

  /// Off the route and being pointed back at it. The plan is still the
  /// active route and nothing is computed: most strays are a wrong turn the
  /// rider undoes themselves within a block.
  guiding,

  /// Off the route long enough that a way back onto it was worked out. The
  /// rejoin is the active route until the plan is under the wheels again.
  detour,
}

/// Which way a point lies from the rider, relative to where they are headed.
enum RelativeDirection {
  /// Roughly the way the rider is already going.
  ahead,

  /// To the left of it.
  left,

  /// To the right of it.
  right,

  /// The way they came.
  behind,
}

/// The way back onto the plan: which point of it to head for, how far it is
/// and which way to turn for it.
///
/// A plain value the banner shows and the voice says; [OffRouteMachine] works
/// one out per fix while the rider is off the route.
class OffRouteGuidance {
  /// Creates the guidance.
  const OffRouteGuidance({
    required this.target,
    required this.distanceM,
    required this.alongM,
    this.direction,
  });

  /// The point of the plan the rider is being sent to: the nearest one that
  /// is still ahead of them along the route.
  final LatLng target;

  /// How far [target] is as the crow flies, in metres. Not the length of the
  /// way there, which is exactly what is not known in this state.
  final double distanceM;

  /// How far along the plan [target] sits, in metres.
  final double alongM;

  /// Which way [target] lies from the rider, or `null` when the rider's
  /// heading is unknown and no direction can honestly be given.
  final RelativeDirection? direction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OffRouteGuidance &&
          other.target == target &&
          other.distanceM == distanceM &&
          other.alongM == alongM &&
          other.direction == direction;

  @override
  int get hashCode => Object.hash(target, distanceM, alongM, direction);

  @override
  String toString() =>
      'OffRouteGuidance(${distanceM.toStringAsFixed(0)} m to '
      '${alongM.toStringAsFixed(0)} m along'
      '${direction != null ? ', ${direction!.name}' : ''})';
}
