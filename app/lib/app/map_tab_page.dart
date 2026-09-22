import 'package:flutter/material.dart';

/// The page of a tab that is chrome over the shell's map: a material page
/// whose route puts no barrier under its content.
///
/// A modal route lays a barrier under its content that takes every touch
/// the content did not, which is what makes a page opaque to touch. The
/// Plan and Record tabs are transparent over the map the shell paints
/// under the branch stack, and a touch that lands on nothing of theirs is
/// meant for that map, so their route leaves the barrier out. Every other
/// route keeps it.
class MapTabPage<T> extends Page<T> {
  /// Creates the page.
  const MapTabPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// The tab.
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _MapTabRoute<T>(page: this);
}

class _MapTabRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _MapTabRoute({required MapTabPage<T> page}) : super(settings: page);

  MapTabPage<T> get _page => settings as MapTabPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => true;

  @override
  bool get fullscreenDialog => false;

  /// Nothing under the tab: the touch falls through to the shell's map.
  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  /// Not opaque, for the same reason: the page transition a page pushed
  /// over this one hands down wraps an opaque route in a box that takes
  /// every touch, transparent or not. The tab is the first route of its
  /// branch, so there is nothing under it that this would keep painted.
  @override
  bool get opaque => false;

  /// No transition of its own either: the platform's page transition
  /// wraps the page in a shadow box that takes every touch, and a branch
  /// root is never pushed or popped with one. A page pushed over the tab
  /// still hands its own transition down through [receivedTransition].
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';
}
