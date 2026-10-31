import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../planner/application/planner_controller.dart';
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
/// then recalculated, and does it: into the plan where it fits along the
/// way, as the Plan tab's own "add as a stop" does. A saved route is first
/// opened in the planner, as from the library, and the ride then follows
/// that copy; the saved route itself is left as it is.
///
/// Guidance follows on its own: the navigator follows the plan and starts
/// over on the new route once it is routed. The ride is recorded throughout.
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
  final recording = ref.read(recordingControllerProvider.notifier);
  final planner = ref.read(plannerControllerProvider.notifier);
  final follow = ref.read(recordingControllerProvider).follow;
  if (follow case FollowSaved(:final id)) {
    final route = await ref.read(routeRepositoryProvider).routeById(id);
    if (route == null || !context.mounted) return;
    planner.loadSavedRoute(route);
    recording.choose(FollowChoice.plan);
  }
  planner.addWaypointAlongRoute(stop.position, name: stop.name);
}
