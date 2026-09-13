import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/app_config.dart';
import '../../../core/permissions/location_permission.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/location_rationale_dialog.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../../planner/presentation/planner_map_host.dart';
import '../../planner/presentation/route_format.dart';
import '../../shared/presentation/stat_tile.dart';
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

  // Called from the map widget's build, so it must not call setState right
  // away; the next frame re-runs build, which pushes the route, the track
  // and the position to the fresh map.
  void _onMapReady(MapController controller) {
    // The builder may hand over the same controller on every build; only a
    // new map needs the redraw, or the rebuild would call this again forever.
    if (identical(_map, controller)) return;
    _map = controller;
    _drawnTrackPoints = -1;
    _drawnRouteId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Pushes the recording to the map: the track line, the puck, and the route
  /// being followed. Called from build, so it only touches the map when
  /// something actually changed.
  void _syncMap(
    RecordingUiState state,
    SavedRoute? route,
    List<LatLng> planned,
  ) {
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
          speedMps: state.snapshot?.speedMps,
        ),
      );
    }
    // A chosen saved route wins; otherwise the route on the Plan tab is the
    // one the rider is about to ride, saved or not.
    final line = route != null
        ? route.geometry.map((p) => p.pos).toList(growable: false)
        : planned;
    final key = route != null
        ? route.id
        : planned.isEmpty
        ? null
        : 'plan:${planned.length}:${planned.first}:${planned.last}';
    if (key != _drawnRouteId) {
      _drawnRouteId = key;
      if (line.isEmpty) {
        unawaited(map.removeRouteLine(followedRouteLineId));
      } else {
        unawaited(
          map.setRouteLine(
            followedRouteLineId,
            line,
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
    final state = ref.watch(recordingControllerProvider);
    final recovery = ref.watch(recordingRecoveryProvider).value;
    if (recovery != null) _handleRecovery(recovery);

    final followed = state.followedRouteId;
    final route = followed == null
        ? null
        : ref.watch(savedRouteProvider(followed)).value;
    final planned = ref.watch(
      plannerControllerProvider.select(
        (p) => p.result?.positions ?? const <LatLng>[],
      ),
    );
    _syncMap(state, route, planned);

    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    double fraction(double dp) => screenHeight <= 0
        ? 0.3
        : ((bottomInset + dp) / screenHeight).clamp(0.06, 0.9);
    // Collapsed: the handle above the navigation bar. Live: the status row
    // and the three key figures. Idle: the start button and the chooser.
    final collapsed = fraction(30);
    final initial = state.isRecording ? fraction(292) : fraction(420);
    final sheetKey = state.isRecording ? 'live' : 'idle';

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: PlannerMapHost(onMapReady: _onMapReady, embedded: true),
          ),
          DraggableScrollableSheet(
            // A fresh sheet per state, so the initial size applies again
            // when a ride starts or ends.
            key: ValueKey(sheetKey),
            initialChildSize: initial,
            minChildSize: collapsed,
            maxChildSize: 0.85,
            snap: true,
            snapSizes: <double>[initial],
            builder: (context, scrollController) => DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Material(
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  side: BorderSide(color: theme.velorki.glassBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: state.isRecording
                    ? _LivePanel(
                        state: state,
                        scrollController: scrollController,
                        bottomInset: bottomInset,
                        keepScreenOn: _keepScreenOn,
                        onKeepScreenOn: (v) => unawaited(_setKeepScreenOn(v)),
                        onPause: () => unawaited(
                          ref
                              .read(recordingControllerProvider.notifier)
                              .pause(),
                        ),
                        onResume: () => unawaited(
                          ref
                              .read(recordingControllerProvider.notifier)
                              .resume(),
                        ),
                        onStop: () => unawaited(_stop()),
                      )
                    : _IdlePanel(
                        state: state,
                        scrollController: scrollController,
                        bottomInset: bottomInset,
                        keepScreenOn: _keepScreenOn,
                        onKeepScreenOn: (v) => unawaited(_setKeepScreenOn(v)),
                        onStart: () => unawaited(_start()),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The drag handle at the top of the sheet.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

enum _RecoveryDecision { resume, finish, discard }

class _IdlePanel extends ConsumerWidget {
  const _IdlePanel({
    required this.state,
    required this.scrollController,
    required this.bottomInset,
    required this.keepScreenOn,
    required this.onKeepScreenOn,
    required this.onStart,
  });

  final RecordingUiState state;
  final ScrollController scrollController;
  final double bottomInset;
  final bool keepScreenOn;
  final ValueChanged<bool> onKeepScreenOn;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final routes = ref.watch(savedRoutesProvider).value ?? const [];
    final hasPlan = ref.watch(
      plannerControllerProvider.select((p) => p.result != null),
    );
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 24),
      children: [
        const _SheetHandle(),
        Text(l10n.recordingIdleTitle, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(l10n.recordingIdleHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            onPressed: state.busy ? null : onStart,
            icon: const Icon(Icons.fiber_manual_record_rounded),
            label: Text(l10n.recordingStart),
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String?>(
          initialValue: state.followedRouteId,
          decoration: InputDecoration(
            labelText: l10n.recordingFollowRoute,
            prefixIcon: const Icon(Icons.route_outlined),
          ),
          items: [
            DropdownMenuItem<String?>(
              child: Text(
                hasPlan ? l10n.recordingFollowPlan : l10n.recordingFollowNone,
              ),
            ),
            for (final route in routes)
              DropdownMenuItem<String?>(
                value: route.id,
                child: Text(route.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) =>
              ref.read(recordingControllerProvider.notifier).selectRoute(value),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: keepScreenOn,
          onChanged: onKeepScreenOn,
          title: Text(l10n.recordingKeepScreenOn),
        ),
        const SizedBox(height: 16),
        SectionCaption(l10n.recordingRecentRides),
        const SizedBox(height: 4),
        const RidesList(limit: 5, shrinkWrap: true),
      ],
    );
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({
    required this.state,
    required this.scrollController,
    required this.bottomInset,
    required this.keepScreenOn,
    required this.onKeepScreenOn,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final RecordingUiState state;
  final ScrollController scrollController;
  final double bottomInset;
  final bool keepScreenOn;
  final ValueChanged<bool> onKeepScreenOn;
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
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 24),
      children: [
        const _SheetHandle(),
        // Everything in view at once: state and elapsed time with the two
        // buttons, then two rows of three figures. Nothing hides below.
        Row(
          children: [
            _StatusPill(label: status, paused: state.isPaused),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                formatClock(snapshot.elapsed),
                style: theme.textTheme.statMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _RoundAction(
              icon: state.isPaused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              tooltip: state.isPaused
                  ? l10n.recordingResume
                  : l10n.recordingPause,
              filled: state.isPaused,
              onPressed: state.busy
                  ? null
                  : state.isPaused
                  ? onResume
                  : onPause,
            ),
            const SizedBox(width: 10),
            _RoundAction(
              icon: Icons.stop_rounded,
              tooltip: l10n.recordingFinish,
              danger: true,
              onPressed: state.busy ? null : onStop,
            ),
          ],
        ),
        const SizedBox(height: 16),
        StatRow(
          children: [
            StatTile(
              label: l10n.statDistance,
              value: formatDistance(l10n, snapshot.distanceM),
              emphasize: !state.isPaused,
            ),
            StatTile(
              label: l10n.statSpeed,
              value: formatSpeed(l10n, snapshot.speedMps),
            ),
            StatTile(
              label: l10n.statAvgSpeed,
              value: formatSpeed(l10n, snapshot.avgSpeedMps),
            ),
          ],
        ),
        const SizedBox(height: 16),
        StatRow(
          children: [
            StatTile(
              label: l10n.statAscent,
              value: formatHeight(l10n, snapshot.ascentM),
              size: StatSize.medium,
            ),
            StatTile(
              label: l10n.statDescent,
              value: formatHeight(l10n, snapshot.descentM),
              size: StatSize.medium,
            ),
            StatTile(
              label: l10n.statMovingTime,
              value: formatClock(snapshot.moving),
              size: StatSize.medium,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: keepScreenOn,
          onChanged: onKeepScreenOn,
          title: Text(l10n.recordingKeepScreenOn),
        ),
      ],
    );
  }
}

/// A 56dp round button: pause/resume in the accent when it resumes, finish
/// in the error colour.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = danger
        ? scheme.errorContainer
        : filled
        ? scheme.primary
        : scheme.surfaceContainerHigh;
    final foreground = danger
        ? scheme.onErrorContainer
        : filled
        ? scheme.onPrimary
        : scheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, size: 28, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// `● RECORDING` with a red dot, or a quiet `PAUSED`.
///
/// Deliberately not animated: a repeating animation never lets a widget test
/// settle, and a steady dot is calmer on the handlebar anyway.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.paused});

  final String label;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dotColor = paused ? scheme.onSurfaceVariant : scheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: paused
                    ? null
                    : [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: theme.textTheme.overline.copyWith(color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
