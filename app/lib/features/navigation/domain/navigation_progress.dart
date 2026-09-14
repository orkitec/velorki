import 'package:velorki_brouter/velorki_brouter.dart';

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

  /// The same progress with [rerouting] set to [value].
  NavigationProgress withRerouting(bool value) => NavigationProgress(
    next: next,
    distanceToNextM: distanceToNextM,
    after: after,
    offRoute: offRoute,
    remainingM: remainingM,
    alongM: alongM,
    arrived: arrived,
    rerouting: value,
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
          other.rerouting == rerouting;

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
  );

  @override
  String toString() =>
      'NavigationProgress(next: ${next?.kind.name ?? '-'} in '
      '${distanceToNextM.toStringAsFixed(0)} m, '
      'after: ${after?.kind.name ?? '-'}, '
      'along ${alongM.toStringAsFixed(0)} m, '
      'remaining ${remainingM.toStringAsFixed(0)} m'
      '${offRoute ? ', off route' : ''}'
      '${rerouting ? ', re-routing' : ''}'
      '${arrived ? ', arrived' : ''})';
}
