import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../navigation/application/navigation_controller.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/domain/route_waypoints.dart' show projectOnTrack;
import '../../planner/domain/planner_state.dart';
import '../../planner/data/route_repository.dart';
import '../../search/domain/search_result.dart';
import '../application/recording_controller.dart';
import '../domain/follow_choice.dart';

/// Whether a stop tapped on the Record tab can be taken into the route:
/// while a ride is recorded and follows a route, the plan's or a saved one.
bool canAddStopMidRide(WidgetRef ref) {
  final recording = ref.read(recordingControllerProvider);
  if (!recording.isRecording) return false;
  return switch (recording.follow) {
    FollowNone() => false,
    FollowPlan() => ref.read(plannerControllerProvider).result != null,
    FollowSaved(:final id) => ref.read(savedRouteProvider(id)).value != null,
  };
}

/// Asks whether [stop] is to be taken into the followed route, which is
/// then recalculated, and does it: into the part of the plan still ahead of
/// the rider, where it fits along the way ([PlannerController.insertStop],
/// which routes a file's own line again only around the stop). A saved
/// route is first opened in the planner, as from the library, and the ride
/// then follows that copy; the saved route itself is left as it is.
///
/// Guidance carries on along the route as it was while the new one is
/// routed ([HeldGuidedRoute]) and starts over on it once it is there. If it
/// cannot be routed, the stop is taken out again, a saved route is followed
/// again, and the rider is told. The ride is recorded throughout.
Future<void> addStopMidRide(
  BuildContext context,
  WidgetRef ref,
  SearchResult stop,
) async {
  final l10n = AppLocalizations.of(context);
  final saved = ref.read(recordingControllerProvider).follow is FollowSaved;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.recordingAddStopTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.recordingAddStopBody),
          if (saved) ...[
            const SizedBox(height: 12),
            Text(l10n.recordingAddStopSavedBody),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.recordingAddStopConfirm),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false) || !context.mounted) return;
  // The ride may have ended, or its route changed, while the dialog was up.
  if (!canAddStopMidRide(ref)) return;
  // The screen may go before the route is there; the container stays.
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final recording = container.read(recordingControllerProvider.notifier);
  final planner = container.read(plannerControllerProvider.notifier);
  final hold = container.read(heldGuidedRouteProvider.notifier);
  final follow = container.read(recordingControllerProvider).follow;
  final riddenM = _riddenAlongM(container);
  hold.hold(container.read(guidedRouteProvider));
  try {
    if (follow case FollowSaved(:final id)) {
      final route = await container.read(routeRepositoryProvider).routeById(id);
      if (route == null) return;
      planner.loadSavedRoute(route);
      recording.choose(FollowChoice.plan);
    }
    final inserted = planner.insertStop(
      stop.position,
      aheadOfM: riddenM,
      name: stop.name,
    );
    final waypoints = container.read(plannerControllerProvider).waypoints;
    if (inserted && await _routed(container)) return;
    // Back to the route as it was: the stop out of the plan again, unless
    // the plan was changed since, and the saved route followed again.
    if (inserted &&
        listEquals(
          container.read(plannerControllerProvider).waypoints,
          waypoints,
        )) {
      planner.undo();
    }
    if (follow is FollowSaved &&
        container.read(recordingControllerProvider).follow is FollowPlan) {
      recording.choose(follow);
    }
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.recordingAddStopFailed)),
    );
  } finally {
    hold.release();
  }
}

/// How far along the followed route the rider has ridden: where the
/// navigator last matched them to it, or, with no guidance running, where
/// their last fix falls on the route. `null` without either.
double? _riddenAlongM(ProviderContainer container) {
  final navigated = container
      .read(navigationControllerProvider.notifier)
      .riddenAlongM;
  if (navigated != null) return navigated;
  final position = container
      .read(recordingControllerProvider)
      .snapshot
      ?.lastPosition;
  final line = container.read(guidedRouteProvider)?.line;
  if (position == null || line == null || line.length < 2) return null;
  return projectOnTrack(line, position).alongM;
}

/// Waits for the planner to finish routing: `true` when it ends with a
/// route, `false` when it fails.
Future<bool> _routed(ProviderContainer container) async {
  bool? outcome(PlannerState plan) =>
      plan.route.isLoading ? null : plan.result != null;
  final now = outcome(container.read(plannerControllerProvider));
  if (now != null) return now;
  final done = Completer<bool>();
  final sub = container.listen(plannerControllerProvider, (previous, next) {
    final settled = outcome(next);
    if (settled != null && !done.isCompleted) done.complete(settled);
  });
  try {
    return await done.future;
  } finally {
    sub.close();
  }
}
