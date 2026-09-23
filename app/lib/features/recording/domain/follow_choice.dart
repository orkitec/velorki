import 'package:flutter/foundation.dart';

/// What the next ride follows: nothing, the route on the Plan tab, or a
/// saved route. Three answers rather than a nullable id, so "no route" is a
/// choice of its own and not the absence of one that means the plan.
@immutable
sealed class FollowChoice {
  const FollowChoice();

  /// Ride without a route.
  static const FollowChoice none = FollowNone();

  /// Ride the route on the Plan tab, when there is one.
  static const FollowChoice plan = FollowPlan();

  /// The saved route's id, or `null` for the other two.
  String? get routeId => switch (this) {
    FollowSaved(:final id) => id,
    _ => null,
  };
}

/// No route.
class FollowNone extends FollowChoice {
  const FollowNone();

  @override
  bool operator ==(Object other) => other is FollowNone;

  @override
  int get hashCode => 0;
}

/// The route on the Plan tab.
class FollowPlan extends FollowChoice {
  const FollowPlan();

  @override
  bool operator ==(Object other) => other is FollowPlan;

  @override
  int get hashCode => 1;
}

/// A saved route, by id.
class FollowSaved extends FollowChoice {
  const FollowSaved(this.id);

  /// The saved route's id.
  final String id;

  @override
  bool operator ==(Object other) => other is FollowSaved && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
