import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_config.dart';
import '../../../core/permissions/location_permission.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/location_rationale_dialog.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../../planner/presentation/planner_map_host.dart';
import '../../planner/presentation/route_format.dart';
import '../application/recording_controller.dart';
import '../data/recording_gateways.dart';
import '../data/recording_recovery.dart';
import '../data/recording_service.dart';
import '../domain/recording_snapshot.dart';
import '../domain/recording_state.dart';
import 'recording_format.dart';
import 'ride_detail_screen.dart';
import 'rides_list.dart';

/// Id of the followed route's line on the map.
const String followedRouteLineId = 'follow';

/// Preference key of the one-time battery-optimisation explanation.
const String batteryPromptShownKey = 'recording.batteryPromptShown';

/// The Record tab: start a ride, watch the numbers, finish it.
class RecordingScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  MapController? _map;
  bool _keepScreenOn = false;
  bool _recoveryHandled = false;
  int _drawnTrackPoints = -1;
  String? _drawnRouteId;

  @override
  void dispose() {
    if (_keepScreenOn) unawaited(ref.read(screenWakeProvider).disable());
    super.dispose();
  }

  // Called from the map widget's build, so it must not call setState.
  void _onMapReady(MapController controller) {
    _map = controller;
    _drawnTrackPoints = -1;
    _drawnRouteId = null;
  }

  /// Pushes the recording to the map: the track line, the puck, and the route
  /// being followed. Called from build, so it only touches the map when
  /// something actually changed.
  void _syncMap(RecordingUiState state, SavedRoute? route) {
    final map = _map;
    if (map == null) return;
    if (state.track.length != _drawnTrackPoints) {
      _drawnTrackPoints = state.track.length;
      unawaited(map.setTrackLine(state.track));
    }
    final position = state.snapshot?.lastPosition;
    if (position != null) {
      unawaited(
        map.setPosition(
          position,
          accuracyM: state.snapshot?.accuracyM,
          headingDeg: state.snapshot?.headingDeg,
        ),
      );
    }
    final routeId = route?.id;
    if (routeId != _drawnRouteId) {
      _drawnRouteId = routeId;
      if (route == null) {
        unawaited(map.removeRouteLine(followedRouteLineId));
      } else {
        unawaited(
          map.setRouteLine(
            followedRouteLineId,
            route.geometry.map((p) => p.pos).toList(growable: false),
            style: RouteLineStyle.preview,
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------- recovery

  void _handleRecovery(RecoveryResult result) {
    if (_recoveryHandled || result is NoRecovery) return;
    _recoveryHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (result) {
        case ReattachRecording(:final state):
          unawaited(_reattach(state));
        case InterruptedRecording():
          unawaited(_askResumeOrFinish(result));
        case NoRecovery():
          break;
      }
    });
  }

  Future<void> _reattach(RecordingState state) async {
    final running = await ref
        .read(recordingControllerProvider.notifier)
        .reattach(state);
    if (running || !mounted) return;
    // The service died between the launch check and now; fall back to the
    // interrupted flow so the journal is not orphaned.
    RecordingRecovery.reset();
    ref.invalidate(recordingRecoveryProvider);
    _recoveryHandled = false;
  }

  Future<void> _askResumeOrFinish(InterruptedRecording recovery) async {
    final l10n = AppLocalizations.of(context);
    final decision = await showDialog<_RecoveryDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.recordingRecoveryTitle),
        content: Text(
          l10n.recordingRecoveryBody(
            formatDate(l10n, recovery.state.startedAt.toLocal()),
            formatDistance(l10n, recovery.stats.distanceM),
            formatDuration(l10n, recovery.stats.movingTime),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_RecoveryDecision.discard),
            child: Text(l10n.recordingRecoveryDiscard),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_RecoveryDecision.finish),
            child: Text(l10n.recordingRecoveryFinish),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_RecoveryDecision.resume),
            child: Text(l10n.recordingRecoveryResume),
          ),
        ],
      ),
    );
    if (!mounted || decision == null) return;
    final controller = ref.read(recordingControllerProvider.notifier);
    switch (decision) {
      case _RecoveryDecision.resume:
        await controller.resumeInterrupted(
          recovery.state,
          notificationTitle: l10n.recordingNotificationTitle,
        );
      case _RecoveryDecision.finish:
        final ride = await controller.finishInterrupted(
          recovery.state,
          rideName: _defaultRideName(l10n, recovery.state.startedAt.toLocal()),
        );
        if (ride != null && mounted) context.go(rideDetailLocation(ride.id));
      case _RecoveryDecision.discard:
        await controller.discardInterrupted(recovery.state);
    }
    RecordingRecovery.reset();
  }

  // -------------------------------------------------------------- actions

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _ensureLocation(l10n, messenger)) return;
    if (!mounted) return;
    await _ensureNotifications(l10n, messenger);
    if (!mounted) return;
    await _maybeAskBatteryOptimization(l10n);
    if (!mounted) return;
    try {
      await ref
          .read(recordingControllerProvider.notifier)
          .start(notificationTitle: l10n.recordingNotificationTitle);
    } on RecordingException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.recordingFailed(error.message))),
      );
    }
  }

  Future<bool> _ensureLocation(
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    final permission = ref.read(locationPermissionControllerProvider.notifier);
    var status = await permission.refresh();
    if (status.canAsk) {
      if (!mounted) return false;
      if (!await showLocationRationaleDialog(context)) return false;
      status = await permission.requestWhenInUse();
    }
    if (status == LocationPermissionStatus.serviceDisabled) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.recordingLocationServiceOff),
          action: SnackBarAction(
            label: l10n.recordingOpenSettings,
            onPressed: () => unawaited(permission.openLocationSettings()),
          ),
        ),
      );
      return false;
    }
    if (!status.isUsable) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.recordingLocationDenied),
          action: SnackBarAction(
            label: l10n.recordingOpenSettings,
            onPressed: () => unawaited(permission.openAppSettings()),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  /// Asks for the notification permission, but does not insist: without it the
  /// foreground service still runs, only its notification stays hidden.
  Future<void> _ensureNotifications(
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    final gateway = ref.read(notificationPermissionProvider);
    if (await gateway.isGranted()) return;
    if (await gateway.request()) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.recordingNotificationDenied)),
    );
  }

  Future<void> _maybeAskBatteryOptimization(AppLocalizations l10n) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(batteryPromptShownKey) ?? false) return;
    final gateway = ref.read(batteryOptimizationProvider);
    if (await gateway.isIgnored()) return;
    if (!mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.recordingBatteryTitle),
        content: Text(l10n.recordingBatteryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.recordingBatteryLater),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.recordingBatteryAllow),
          ),
        ],
      ),
    );
    await prefs.setBool(batteryPromptShownKey, true);
    if (allow ?? false) await gateway.request();
  }

  Future<void> _stop() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ride = await ref
        .read(recordingControllerProvider.notifier)
        .stop(rideName: _defaultRideName(l10n, DateTime.now()));
    if (ride == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.recordingNothingRecorded)),
      );
      return;
    }
    if (mounted) context.go(rideDetailLocation(ride.id));
  }

  Future<void> _setKeepScreenOn(bool value) async {
    setState(() => _keepScreenOn = value);
    final wake = ref.read(screenWakeProvider);
    await (value ? wake.enable() : wake.disable());
  }

  static String _defaultRideName(AppLocalizations l10n, DateTime date) =>
      l10n.recordingRideName(formatDate(l10n, date));

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(recordingControllerProvider);
    final recovery = ref.watch(recordingRecoveryProvider).value;
    if (recovery != null) _handleRecovery(recovery);

    final followed = state.followedRouteId;
    final route = followed == null
        ? null
        : ref.watch(savedRouteProvider(followed)).value;
    _syncMap(state, route);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabRecord),
        actions: [
          IconButton(
            tooltip: l10n.recordingKeepScreenOn,
            isSelected: _keepScreenOn,
            icon: const Icon(Icons.lightbulb_outline),
            selectedIcon: const Icon(Icons.lightbulb),
            onPressed: () => unawaited(_setKeepScreenOn(!_keepScreenOn)),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 240, child: PlannerMapHost(onMapReady: _onMapReady)),
          Expanded(
            child: state.isRecording
                ? _LivePanel(
                    state: state,
                    onPause: () => unawaited(
                      ref.read(recordingControllerProvider.notifier).pause(),
                    ),
                    onResume: () => unawaited(
                      ref.read(recordingControllerProvider.notifier).resume(),
                    ),
                    onStop: () => unawaited(_stop()),
                  )
                : _IdlePanel(
                    state: state,
                    keepScreenOn: _keepScreenOn,
                    onKeepScreenOn: (v) => unawaited(_setKeepScreenOn(v)),
                    onStart: () => unawaited(_start()),
                  ),
          ),
        ],
      ),
    );
  }
}

enum _RecoveryDecision { resume, finish, discard }

class _IdlePanel extends ConsumerWidget {
  const _IdlePanel({
    required this.state,
    required this.keepScreenOn,
    required this.onKeepScreenOn,
    required this.onStart,
  });

  final RecordingUiState state;
  final bool keepScreenOn;
  final ValueChanged<bool> onKeepScreenOn;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final routes = ref.watch(savedRoutesProvider).value ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(l10n.recordingIdleTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          l10n.recordingIdleHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: state.busy ? null : onStart,
            icon: const Icon(Icons.play_arrow),
            label: Text(l10n.recordingStart),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          initialValue: state.followedRouteId,
          decoration: InputDecoration(
            labelText: l10n.recordingFollowRoute,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<String?>(child: Text(l10n.recordingFollowNone)),
            for (final route in routes)
              DropdownMenuItem<String?>(
                value: route.id,
                child: Text(route.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) =>
              ref.read(recordingControllerProvider.notifier).selectRoute(value),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: keepScreenOn,
          onChanged: onKeepScreenOn,
          title: Text(l10n.recordingKeepScreenOn),
        ),
        const Divider(height: 32),
        Text(l10n.recordingRecentRides, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const RidesList(limit: 5, shrinkWrap: true),
      ],
    );
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({
    required this.state,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final RecordingUiState state;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final snapshot = state.snapshot!;
    final status = switch (snapshot) {
      RecordingSnapshot(status: RecordingStatus.paused, autoPaused: true) =>
        l10n.recordingStatusAutoPaused,
      RecordingSnapshot(status: RecordingStatus.paused) =>
        l10n.recordingStatusPaused,
      _ => l10n.recordingStatusRecording,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Icon(
              state.isPaused ? Icons.pause_circle : Icons.fiber_manual_record,
              size: 16,
              color: state.isPaused
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: 6),
            Text(status, style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          formatDistance(l10n, snapshot.distanceM),
          style: theme.textTheme.displaySmall,
        ),
        const SizedBox(height: 12),
        RideStatsGrid(
          items: <RideStatItem>[
            RideStatItem(
              icon: Icons.timelapse,
              label: l10n.statElapsed,
              value: formatClock(snapshot.elapsed),
            ),
            RideStatItem(
              icon: Icons.schedule,
              label: l10n.statMovingTime,
              value: formatClock(snapshot.moving),
            ),
            RideStatItem(
              icon: Icons.speed,
              label: l10n.statSpeed,
              value: formatSpeed(l10n, snapshot.speedMps),
            ),
            RideStatItem(
              icon: Icons.trending_flat,
              label: l10n.statAvgSpeed,
              value: formatSpeed(l10n, snapshot.avgSpeedMps),
            ),
            RideStatItem(
              icon: Icons.trending_up,
              label: l10n.statAscent,
              value: formatHeight(l10n, snapshot.ascentM),
            ),
            RideStatItem(
              icon: Icons.trending_down,
              label: l10n.statDescent,
              value: formatHeight(l10n, snapshot.descentM),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: state.isPaused
                    ? FilledButton.icon(
                        onPressed: state.busy ? null : onResume,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l10n.recordingResume),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: state.busy ? null : onPause,
                        icon: const Icon(Icons.pause),
                        label: Text(l10n.recordingPause),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: state.busy ? null : onStop,
                  icon: const Icon(Icons.stop),
                  label: Text(l10n.recordingFinish),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
