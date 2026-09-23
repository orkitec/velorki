import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/theme.dart';
import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/presentation/profile_chip_row.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/smart_loop_controller.dart';
import '../data/loop_preferences.dart';
import '../domain/loops.dart';

/// Opens the "Make a loop" sheet over the planner.
///
/// [map] is the planner's own map controller, used as the fallback start when
/// there is no plan and no position. The sheet draws nothing itself: the loop
/// it makes goes straight into the planner, which already draws its route.
Future<void> showSmartLoopSheet(
  BuildContext context, {
  MapController? map,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  // A search the assistant has just started keeps running; anything older is
  // stale the moment the sheet opens again.
  if (!container.read(smartLoopControllerProvider).running) {
    container.read(smartLoopControllerProvider.notifier).reset();
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // The shell's floating navigation bar belongs to the branch navigator, so
    // a sheet opened there would sit under it.
    useRootNavigator: true,
    builder: (context) => SmartLoopSheet(map: map),
  );
  container.read(smartLoopControllerProvider.notifier).cancel();
}

/// One sheet, two jobs: close the planned route into a loop, or make a loop
/// out of nothing but a start and a distance.
///
/// Which of the two it is, is not a choice the rider has to make — it follows
/// from what is on the map. With a route planned, "a loop" means riding that
/// route and coming home; with a bare start it means going somewhere and
/// coming back.
class SmartLoopSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const SmartLoopSheet({super.key, this.map});

  /// The planner's map, for the map-centre fallback.
  final MapController? map;

  @override
  ConsumerState<SmartLoopSheet> createState() => _SmartLoopSheetState();
}

class _SmartLoopSheetState extends ConsumerState<SmartLoopSheet> {
  /// Whether the sheet closes the planned route (Case A) rather than making a
  /// loop from scratch (Case B). Decided once, when the sheet opens.
  late final bool _closeRoute;

  /// Whether the loop starts at a point the rider put on the map. Read once:
  /// adopting a loop puts its own start waypoint in the planner, and the line
  /// under the title must not change meaning because of that.
  late final bool _startIsPlotted;
  late double _km;
  bool _differentWayBack = true;

  /// Whether the plan is a loop already, which is when the sheet shows what it
  /// made instead of offering to make it.
  bool _closed = false;
  bool _fromMapCentre = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    final loop = ref.read(smartLoopControllerProvider);
    final planner = ref.read(plannerControllerProvider);
    // A running or finished search owns the planner's route, so the sheet
    // stays on the search it belongs to.
    final searching = loop.running || loop.candidates.isNotEmpty;
    _closeRoute = !searching && planner.waypoints.length >= 2;
    _startIsPlotted = planner.waypoints.isNotEmpty;
    _closed = planner.isClosedLoop;
    if (_closed) _differentWayBack = planner.options.differentWayBack;
    _km = _snapped(
      loop.request != null
          ? loop.request!.targetM / 1000
          : ref.read(lastLoopDistanceKmProvider),
    );
  }

  /// [km] moved to the nearest stop the slider actually has.
  ///
  /// The stops are whole kilometres or whole miles, so a distance last chosen
  /// in one unit does not leave the figure sitting between two of them after
  /// the rider switches to the other.
  double _snapped(double km) {
    final system = ref.read(unitSystemProvider);
    final metric = system == UnitSystem.metric;
    final min = metric ? loopMinKm : loopMinMi;
    final max = metric ? loopMaxKm : loopMaxMi;
    final step = metric ? loopStepKm : loopStepMi;
    final display = units.distanceToDisplay(system, km * 1000).clamp(min, max);
    final stops = ((display - min) / step).round();
    return units.displayToMeters(system, min + stops * step) / 1000;
  }

  /// Where a from-scratch loop starts: the plotted waypoint, else the rider's
  /// position, else what the map is looking at.
  Future<LatLng?> _resolveStart() async {
    final waypoints = ref.read(plannerControllerProvider).waypoints;
    if (waypoints.isNotEmpty) return waypoints.first.pos;
    final position = await requestDevicePosition(context, ref);
    if (position != null) return position;
    final centre = widget.map?.center;
    if (centre != null && mounted) setState(() => _fromMapCentre = true);
    return centre;
  }

  Future<void> _make() async {
    final l10n = AppLocalizations.of(context);
    final profile = ref.read(plannerControllerProvider).options.profile;
    final previous = ref.read(smartLoopControllerProvider).request;
    final start = await _resolveStart();
    if (!mounted) return;
    if (start == null) {
      setState(() => _problem = l10n.loopNoPosition);
      return;
    }
    setState(() => _problem = null);
    unawaited(ref.read(lastLoopDistanceKmProvider.notifier).save(_km));
    await ref
        .read(smartLoopControllerProvider.notifier)
        .search(
          LoopRequest(
            start: start,
            targetM: _km * 1000,
            profile: profile.brouterName,
            // The rider's own preferences only ever arrive from the
            // assistant; the sheet itself has no opinion any more.
            prefs: previous?.prefs ?? const LoopPrefs(),
          ),
          allowSameWayBack: !_differentWayBack,
        );
  }

  void _close() {
    ref
        .read(plannerControllerProvider.notifier)
        .closeLoop(differentWayBack: _differentWayBack);
    // The sheet stays: what it just made is the thing the rider wants to look
    // at, and "Another way back" is the next thing they will want.
    setState(() => _closed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewPaddingOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.loopMakeTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (_closeRoute) ..._closeRouteBody(l10n, theme),
            if (!_closeRoute) ..._makeLoopBody(l10n, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _closeRouteBody(AppLocalizations l10n, ThemeData theme) {
    final planner = ref.watch(plannerControllerProvider);
    final system = ref.watch(unitSystemProvider);
    final result = planner.result;
    return [
      Text(l10n.loopBackToStart, style: _quiet(theme)),
      ..._profileSection(l10n),
      _wayBackSwitch(l10n),
      const SizedBox(height: 12),
      if (!_closed)
        SizedBox(
          height: primaryButtonHeight,
          child: FilledButton.icon(
            onPressed: _close,
            icon: const Icon(Icons.loop_rounded),
            label: Text(l10n.loopClose),
          ),
        )
      else ...[
        if (planner.isRouting)
          _LoopProgress(value: null)
        else if (result != null)
          Text(
            l10n.loopResult(
              formatDistance(l10n, system, result.lengthM),
              formatHeight(l10n, system, result.ascentM),
            ),
            style: theme.textTheme.titleMedium,
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: planner.isRouting || !planner.ridesBackAnotherWay
                    ? null
                    : () => unawaited(
                        ref
                            .read(plannerControllerProvider.notifier)
                            .anotherWayBack(),
                      ),
                child: Text(l10n.loopAnotherWayBack),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: Navigator.of(context).pop,
                child: Text(l10n.loopDone),
              ),
            ),
          ],
        ),
        if (planner.error != null)
          _Problem(text: l10n.loopFailed(planner.error!)),
      ],
    ];
  }

  /// The bike the loop is routed for. It is the planner's own profile, so
  /// picking one here changes the chips on the planner too.
  List<Widget> _profileSection(AppLocalizations l10n) => [
    const SizedBox(height: 16),
    SectionCaption(l10n.loopProfile),
    const SizedBox(height: 8),
    ProfileChipRow(
      selected: ref.watch(plannerControllerProvider).options.profile,
      onSelected: ref.read(plannerControllerProvider.notifier).setProfile,
    ),
  ];

  List<Widget> _makeLoopBody(AppLocalizations l10n, ThemeData theme) {
    final state = ref.watch(smartLoopControllerProvider);
    final profile = ref.watch(plannerControllerProvider).options.profile;
    final system = ref.watch(unitSystemProvider);
    final metric = system == UnitSystem.metric;
    // The slider works in whatever the rider reads; only the kilometres it
    // hands back are ever stored or routed for.
    final sliderMin = metric ? loopMinKm : loopMinMi;
    final sliderMax = metric ? loopMaxKm : loopMaxMi;
    final sliderStep = metric ? loopStepKm : loopStepMi;
    final sliderValue = units
        .distanceToDisplay(system, _km * 1000)
        .clamp(sliderMin, sliderMax);
    final result = state.current?.result;
    // Moving the slider or picking another bike after a search makes the loop
    // on the map stale, so the sheet offers to make a new one rather than
    // another one.
    final stale =
        state.request != null &&
        ((state.request!.targetM / 1000 - _km).abs() > 0.01 ||
            state.request!.profile != profile.brouterName);

    return [
      if (!_startIsPlotted)
        Text(
          _fromMapCentre ? l10n.loopFromMapCentre : l10n.loopFromPosition,
          style: _quiet(theme),
        ),
      const SizedBox(height: 16),
      SectionCaption(l10n.loopDistance),
      const SizedBox(height: 4),
      Text(
        _sliderLabel(l10n, system, sliderValue),
        style: theme.textTheme.statLarge.copyWith(color: theme.velorki.accent),
      ),
      Slider(
        value: sliderValue,
        min: sliderMin,
        max: sliderMax,
        divisions: ((sliderMax - sliderMin) / sliderStep).round(),
        label: _sliderLabel(l10n, system, sliderValue),
        onChanged: state.running
            ? null
            : (v) =>
                  setState(() => _km = units.displayToMeters(system, v) / 1000),
      ),
      ..._profileSection(l10n),
      _wayBackSwitch(l10n),
      const SizedBox(height: 12),
      if (state.running) ...[
        // Indeterminate until the first request has come back: a bar sitting
        // empty at 0 % while the first batch routes looked frozen.
        _LoopProgress(value: state.progress > 0 ? state.progress : null),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: ref.read(smartLoopControllerProvider.notifier).cancel,
            child: Text(l10n.loopStop),
          ),
        ),
      ] else if (result != null && !stale) ...[
        Text(
          l10n.loopResult(
            formatDistance(l10n, system, result.lengthM),
            formatHeight(l10n, system, result.ascentM),
          ),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => unawaited(
                  ref.read(smartLoopControllerProvider.notifier).another(),
                ),
                child: Text(l10n.loopAnother),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: Navigator.of(context).pop,
                child: Text(l10n.loopDone),
              ),
            ),
          ],
        ),
      ] else
        SizedBox(
          height: primaryButtonHeight,
          child: FilledButton.icon(
            onPressed: () => unawaited(_make()),
            icon: const Icon(Icons.loop_rounded),
            label: Text(l10n.loopMake),
          ),
        ),
      if (state.foundNothing && !state.running)
        _Problem(text: l10n.loopNoneFound),
      if (state.error != null) _Problem(text: l10n.loopFailed(state.error!)),
      if (_problem != null) _Problem(text: _problem!),
    ];
  }

  /// The slider figure. It only ever moves in whole kilometres or miles, so
  /// the decimal the route statistics carry would be a permanent ".0" here.
  String _sliderLabel(AppLocalizations l10n, UnitSystem system, double value) =>
      formatMeasure(
        l10n,
        units.Measure(
          value,
          system == UnitSystem.metric
              ? units.MeasureUnit.kilometers
              : units.MeasureUnit.miles,
        ),
      );

  Widget _wayBackSwitch(AppLocalizations l10n) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(l10n.loopDifferentWayBack),
    subtitle: Text(l10n.loopDifferentWayBackHint),
    value: _differentWayBack,
    onChanged: (v) {
      setState(() => _differentWayBack = v);
      // A loop that is already on the map is redrawn on the spot; one that is
      // not yet made only remembers the choice.
      if (_closed) {
        ref
            .read(plannerControllerProvider.notifier)
            .closeLoop(differentWayBack: v);
      }
    },
  );

  TextStyle? _quiet(ThemeData theme) => theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
}

/// The search's progress bar: animated while [value] is `null`, filled to
/// [value] once there is one, the same height and track either way so the
/// switch moves nothing.
class _LoopProgress extends StatelessWidget {
  const _LoopProgress({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 4,
      // A track the bar is visibly drawn on in both themes, rather than the
      // indicator's own faint default.
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
