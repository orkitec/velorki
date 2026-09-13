import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/domain/route_profile.dart';
import '../../planner/presentation/route_format.dart';
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
    _km = loop.request != null
        ? loop.request!.targetM / 1000
        : ref.read(lastLoopDistanceKmProvider);
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
    final result = planner.result;
    return [
      Text(l10n.loopBackToStart, style: _quiet(theme)),
      ..._profileSection(l10n),
      _wayBackSwitch(l10n),
      const SizedBox(height: 12),
      if (!_closed)
        FilledButton.icon(
          onPressed: _close,
          icon: const Icon(Icons.loop_rounded),
          label: Text(l10n.loopClose),
        )
      else ...[
        if (planner.isRouting)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(minHeight: 4),
          )
        else if (result != null)
          Text(
            l10n.loopResult(
              formatDistance(l10n, result.lengthM),
              formatHeight(l10n, result.ascentM),
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
    _ProfileChips(
      selected: ref.watch(plannerControllerProvider).options.profile,
      onSelected: ref.read(plannerControllerProvider.notifier).setProfile,
    ),
  ];

  List<Widget> _makeLoopBody(AppLocalizations l10n, ThemeData theme) {
    final state = ref.watch(smartLoopControllerProvider);
    final profile = ref.watch(plannerControllerProvider).options.profile;
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
        _kmLabel(l10n),
        style: theme.textTheme.statLarge.copyWith(color: theme.velorki.accent),
      ),
      Slider(
        value: _km,
        min: loopMinKm,
        max: loopMaxKm,
        divisions: ((loopMaxKm - loopMinKm) / loopStepKm).round(),
        label: _kmLabel(l10n),
        onChanged: state.running ? null : (v) => setState(() => _km = v),
      ),
      ..._profileSection(l10n),
      _wayBackSwitch(l10n),
      const SizedBox(height: 12),
      if (state.running) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: state.progress, minHeight: 4),
        ),
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
            formatDistance(l10n, result.lengthM),
            formatHeight(l10n, result.ascentM),
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
        FilledButton.icon(
          onPressed: () => unawaited(_make()),
          icon: const Icon(Icons.loop_rounded),
          label: Text(l10n.loopMake),
        ),
      if (state.foundNothing && !state.running)
        _Problem(text: l10n.loopNoneFound),
      if (state.error != null) _Problem(text: l10n.loopFailed(state.error!)),
      if (_problem != null) _Problem(text: _problem!),
    ];
  }

  /// The slider figure. It only ever moves in whole steps of
  /// [loopStepKm] kilometres, so the decimal the route statistics carry would
  /// be a permanent ".0" here.
  String _kmLabel(AppLocalizations l10n) =>
      l10n.valueKilometers(formatNumber(l10n, _km, decimals: 0));

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

/// The planner's profiles as a scrolling row of chips.
///
/// The planner draws the same choice over the map, where the chips have to be
/// opaque glass; here the sheet is a surface already, so the chip theme is
/// left alone.
class _ProfileChips extends StatelessWidget {
  const _ProfileChips({required this.selected, required this.onSelected});

  final RouteProfile selected;
  final ValueChanged<RouteProfile> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final profile in RouteProfile.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(profileLabel(l10n, profile)),
                selected: profile == selected,
                onSelected: (_) => onSelected(profile),
              ),
            ),
        ],
      ),
    );
  }
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
