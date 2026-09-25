import 'package:flutter/foundation.dart' show listEquals;
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'off_route_guidance.dart';
import '../../planner/domain/route_poi.dart';

/// Where the rider stands on a route: the turn that is coming, the one after
/// it, how much route is left and whether the rider is still on it.
///
/// A plain value with no behaviour; [TurnNavigator] produces one per position
/// fix and [TurnAnnouncer] turns a stream of them into spoken cues.
class NavigationProgress {
  /// Creates a progress value. The defaults describe a rider who has not been
  /// located yet: no turn ahead, nothing covered, still on the route.
  const NavigationProgress({
    this.next,
    this.distanceToNextM = 0,
    this.after,
    this.offRoute = false,
    this.remainingM = 0,
    this.alongM = 0,
    this.arrived = false,
    this.rerouting = false,
    this.snapped,
    this.routeBearingDeg,
    this.distanceFromRouteM = 0,
    this.offRouteState = OffRouteState.onRoute,
    this.guidance,
    this.poi,
    this.distanceToPoiM = 0,
    this.stopsAhead = const <LatLng>[],
  });

  /// The turn that has not been passed yet, or `null` when none is left.
  ///
  /// Only turns worth announcing appear here: carrying on straight, a beeline
  /// and BRouter's "off road" marker are skipped.
  final TurnHint? next;

  /// Distance along the route from the rider to [next], in metres. Never
  /// negative; 0 once the rider is level with the turn.
  final double distanceToNextM;

  /// The turn after [next], for a "then keep right" preview. Same filter.
  final TurnHint? after;

  /// Whether the rider has strayed from the route.
  final bool offRoute;

  /// Distance from the rider to the end of the route, in metres.
  final double remainingM;

  /// Distance from the start of the route to the rider, in metres.
  final double alongM;

  /// Whether the rider has reached the end of the route.
  final bool arrived;

  /// Whether a new way back onto the route is being computed right now.
  ///
  /// Set by the controller rather than the navigator: it is about a request in
  /// flight, not about where the rider is.
  final bool rerouting;

  /// The point of the route the rider was matched to, or `null` before the
  /// first fix.
  ///
  /// A GPS fix wanders by a few metres from one second to the next; the
  /// matched point does not, which is why the puck is drawn here while the
  /// rider is on the route.
  final LatLng? snapped;

  /// Forward bearing of the route at [snapped], in degrees clockwise from
  /// north, or `null` when the route is a single point.
  ///
  /// Steadier than a GNSS course by a long way: it is the direction the road
  /// runs, not the direction the last two fixes happened to fall in.
  final double? routeBearingDeg;

  /// How far the fix was from the route, in metres. The caller decides how
  /// much of a gap is still worth snapping over.
  final double distanceFromRouteM;

  /// Where the ride stands in relation to the route it was planned along.
  ///
  /// Not the same question as [offRoute], which is about the route being
  /// navigated right now: a rider following a rejoin is on that route and
  /// off the plan at the same time.
  final OffRouteState offRouteState;

  /// The way back onto the plan while [offRouteState] is
  /// [OffRouteState.guiding], `null` otherwise.
  final OffRouteGuidance? guidance;

  /// The next point of interest ahead on the plan, or `null` when none is
  /// left or the rider is off the plan. From the controller.
  final RoutePoi? poi;

  /// Distance along the plan from the rider to [poi], in metres.
  final double distanceToPoiM;

  /// The same progress with the controller's own fields filled in.
  ///
  /// The navigator knows nothing about re-routing or about the plan a rider
  /// has left, so those three come from [NavigationController].
  /// The points of the plan the rider has still to reach, the destination
  /// included, in order: what is not among them is behind them.
  final List<LatLng> stopsAhead;

  NavigationProgress decorated({
    required bool rerouting,
    required OffRouteState offRouteState,
    OffRouteGuidance? guidance,
    RoutePoi? poi,
    double distanceToPoiM = 0,
    List<LatLng> stopsAhead = const <LatLng>[],
  }) => NavigationProgress(
    next: next,
    distanceToNextM: distanceToNextM,
    after: after,
    offRoute: offRoute,
    remainingM: remainingM,
    alongM: alongM,
    arrived: arrived,
    rerouting: rerouting,
    snapped: snapped,
    routeBearingDeg: routeBearingDeg,
    distanceFromRouteM: distanceFromRouteM,
    offRouteState: offRouteState,
    guidance: guidance,
    poi: poi,
    distanceToPoiM: distanceToPoiM,
    stopsAhead: stopsAhead,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationProgress &&
          other.next == next &&
          other.distanceToNextM == distanceToNextM &&
          other.after == after &&
          other.offRoute == offRoute &&
          other.remainingM == remainingM &&
          other.alongM == alongM &&
          other.arrived == arrived &&
          other.rerouting == rerouting &&
          other.snapped == snapped &&
          other.routeBearingDeg == routeBearingDeg &&
          other.distanceFromRouteM == distanceFromRouteM &&
          other.offRouteState == offRouteState &&
          other.guidance == guidance &&
          other.poi == poi &&
          other.distanceToPoiM == distanceToPoiM &&
          listEquals(other.stopsAhead, stopsAhead);

  @override
  int get hashCode => Object.hash(
    next,
    distanceToNextM,
    after,
    offRoute,
    remainingM,
    alongM,
    arrived,
    rerouting,
    snapped,
    routeBearingDeg,
    distanceFromRouteM,
    offRouteState,
    guidance,
  );

  @override
  String toString() =>
      'NavigationProgress(next: ${next?.kind.name ?? '-'} in '
      '${distanceToNextM.toStringAsFixed(0)} m, '
      'after: ${after?.kind.name ?? '-'}, '
      'along ${alongM.toStringAsFixed(0)} m, '
      'remaining ${remainingM.toStringAsFixed(0)} m'
      '${offRoute ? ', off route' : ''}'
      '${offRouteState != OffRouteState.onRoute ? ', ${offRouteState.name}' : ''}'
      '${rerouting ? ', re-routing' : ''}'
      '${arrived ? ', arrived' : ''})';
}
