import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/domain/avoid_area.dart';
import '../../planner/domain/route_profile.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/assistant_controller.dart';
import '../application/route_advice_controller.dart';
import '../data/ai_consent_controller.dart';
import '../domain/ai_consent.dart';
import '../domain/assistant_state.dart';
import '../domain/intent_resolver.dart';
import 'ai_consent_dialog.dart';
import 'assistant_strings.dart';

/// Opens the assistant over the planner.
///
/// Answers with the intent that was handed over — a [LoopIntent] means a loop
/// search is already running and the caller should show the loop sheet, a
/// [RouteIntent] means the waypoints are on the map — or `null` when the
/// rider closed the sheet without a result.
Future<ResolvedIntent?> showAssistantSheet(
  BuildContext context, {
  MapController? map,
}) => showModalBottomSheet<ResolvedIntent>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Over the shell's floating navigation bar, not under it.
  useRootNavigator: true,
  builder: (context) => AssistantSheet(map: map),
);

/// What the assistant sheet is asked about.
enum AssistantMode {
  /// A new route, from a sentence: what the sheet always did.
  newRoute,

  /// The route on the planner's map.
  thisRoute,
}

/// "A hilly 60 km loop from here past the lake", as a text field; or, with a
/// route on the map, a question about it.
class AssistantSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const AssistantSheet({super.key, this.map});

  /// The planner's map, used to bias the geocoder towards what is on screen
  /// and to show what an answer about the route points at.
  final MapController? map;

  @override
  ConsumerState<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends ConsumerState<AssistantSheet> {
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _question = TextEditingController();
  final GlobalKey _sheetKey = GlobalKey();

  /// Whether the route on the map may be asked about, decided when the
  /// sheet opens: a fix being applied re-routes the plan, and the choice of
  /// modes must not flicker while it does.
  late final bool _routeAvailable;
  late AssistantMode _mode;

  @override
  void initState() {
    super.initState();
    _prompt.text = ref.read(assistantControllerProvider).prompt;
    _routeAvailable = canAskAboutRoute(ref.read(plannerControllerProvider));
    _mode = _routeAvailable ? AssistantMode.thisRoute : AssistantMode.newRoute;
    _empty = _field.text.trim().isEmpty;
    // The chips under the field follow what is in it.
    _prompt.addListener(_promptChanged);
    _question.addListener(_promptChanged);
  }

  bool _empty = true;

  TextEditingController get _field =>
      _mode == AssistantMode.thisRoute ? _question : _prompt;

  void _promptChanged() {
    final empty = _field.text.trim().isEmpty;
    if (empty != _empty) setState(() => _empty = empty);
  }

  void _setMode(AssistantMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _empty = _field.text.trim().isEmpty;
    });
  }

  /// Appends [wish] to what the rider typed.
  void _add(String wish) {
    final text = _prompt.text.trimRight();
    final sep = text.isEmpty || text.endsWith(',') ? ' ' : ', ';
    _prompt.value = TextEditingValue(
      text: '$text$sep$wish',
      selection: TextSelection.collapsed(offset: '$text$sep$wish'.length),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _prompt
      ..removeListener(_promptChanged)
      ..dispose();
    _question
      ..removeListener(_promptChanged)
      ..dispose();
    super.dispose();
  }

  /// The wishes the planner acts on that the prompt does not mention yet.
  List<String> _wishes(AppLocalizations l10n) {
    final said = _prompt.text.toLowerCase();
    return <String>[
      l10n.assistantRefineFlat,
      l10n.assistantRefineHilly,
      l10n.assistantRefineGravel,
      l10n.assistantRefineQuiet,
      l10n.assistantRefineLoop,
    ].where((w) => !said.contains(w.toLowerCase())).toList(growable: false);
  }

  /// The questions offered about the route on the map.
  List<String> _routeExamples(AppLocalizations l10n) => <String>[
    l10n.assistantRouteExampleCheck,
    l10n.assistantRouteExampleCoffee,
    l10n.assistantRouteExampleWater,
    l10n.assistantRouteExampleAvoid,
    l10n.assistantRouteExampleRoadBike,
  ];

  /// Makes sure there is a consent, asking for one exactly once.
  ///
  /// Answers `null` when the rider dismissed the dialog or refused, in which
  /// case nothing is sent and nothing is said.
  Future<AiConsent?> _ensureConsent() async {
    final stored = ref.read(aiConsentControllerProvider);
    if (stored != null && stored.allowsRequests) return stored;
    final choice = await showAiConsentDialog(context);
    if (choice == null) return null;
    await ref.read(aiConsentControllerProvider.notifier).set(choice);
    return choice.allowsRequests ? choice : null;
  }

  Future<void> _send() async {
    if (_mode == AssistantMode.thisRoute) return _askAboutRoute();
    final text = _prompt.text.trim();
    if (text.isEmpty) return;
    final consent = await _ensureConsent();
    if (consent == null || !mounted) return;
    // The position is needed locally in any case — "from here" is resolved on
    // the phone — and is only ever *sent* with AiConsent.withLocation.
    final position = await requestDevicePosition(context, ref);
    if (!mounted) return;
    await ref
        .read(assistantControllerProvider.notifier)
        .submit(text, position: position, bias: widget.map?.center);
  }

  /// Asks about the route on the map. No position is asked for: the route
  /// is what the question is about.
  Future<void> _askAboutRoute() async {
    final text = _question.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    final consent = await _ensureConsent();
    if (consent == null || !mounted) return;
    await ref.read(routeAdviceControllerProvider.notifier).ask(text);
  }

  Future<void> _choose(String query, ResolvedPlace place) async {
    final position = await requestDevicePosition(context, ref);
    if (!mounted) return;
    await ref
        .read(assistantControllerProvider.notifier)
        .choose(query, place, position: position, bias: widget.map?.center);
  }

  /// What of the map is not under this sheet, as padding for the camera.
  EdgeInsets _uncovered() {
    final media = MediaQuery.of(context);
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    final covered = box == null || !box.hasSize ? 0.0 : box.size.height;
    final room = media.size.height - covered;
    // A sheet that leaves next to nothing still gets a sliver to aim at.
    final bottom = room < 160 ? media.size.height - 160 : covered + 24;
    return EdgeInsets.fromLTRB(32, media.padding.top + 32, 32, bottom);
  }

  /// Moves the map to what finding [finding] is about: its place, or its
  /// stretch of the route on the map.
  void _show(RouteFinding finding, RouteAdviceState advice) {
    final map = widget.map;
    if (map == null) return;
    final place = advice.placeOf(finding.placeId ?? _stopOf(finding));
    final padding = _uncovered();
    if (place != null) {
      unawaited(
        map.moveTo(
          LatLng(place.at.lat, place.at.lon),
          zoom: 15,
          padding: padding,
        ),
      );
      return;
    }
    final route = ref.read(plannerControllerProvider).result ?? advice.route;
    final from = finding.fromKm;
    if (route == null || from == null) return;
    final to = finding.toKm ?? from;
    final piece = AvoidArea.cut(
      route.positions,
      from * 1000,
      math.max(to * 1000, from * 1000 + 1),
    );
    if (piece.isEmpty) return;
    if (to - from < 0.2) {
      unawaited(map.moveTo(piece.first, zoom: 15, padding: padding));
    } else {
      unawaited(map.fitBounds(BoundingBox.fromPoints(piece), padding: padding));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(assistantControllerProvider);
    final advice = ref.watch(routeAdviceControllerProvider);
    final aboutRoute = _mode == AssistantMode.thisRoute;
    final busy = aboutRoute ? advice.busy : state.busy;

    ref.listen(assistantControllerProvider, (previous, next) {
      if (next.phase != AssistantPhase.ready || !mounted) return;
      // Everything that could be done has been done: a loop search is running
      // or the waypoints are on the map. The planner takes it from here.
      Navigator.of(context).pop(next.intent);
    });

    // On a short screen — a phone held sideways — the heading scrolls with
    // the rest, so the answer is not left a sliver under it.
    final short = MediaQuery.sizeOf(context).height < 520;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(short ? 0 : 20, 4, short ? 0 : 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Only with a route to ask about is there a choice.
          if (_routeAvailable) ...[
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AssistantMode>(
                segments: [
                  ButtonSegment(
                    value: AssistantMode.thisRoute,
                    label: Text(l10n.assistantModeRoute),
                    icon: const Icon(Icons.route_rounded),
                  ),
                  ButtonSegment(
                    value: AssistantMode.newRoute,
                    label: Text(l10n.assistantModeNew),
                    icon: const Icon(Icons.add_road_rounded),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: busy
                    ? null
                    : (selected) => _setMode(selected.single),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            aboutRoute ? l10n.assistantRouteTitle : l10n.assistantTitle,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          // What leaves the phone and what does not: said in the
          // reading size, not in fine print.
          Text(
            aboutRoute ? l10n.assistantRouteIntro : l10n.assistantIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return ConstrainedBox(
      key: _sheetKey,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!short) header,
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                children: [
                  if (short) header,
                  TextField(
                    // Keyed by mode, so each keeps its own text and undo.
                    key: ValueKey(_mode),
                    controller: _field,
                    minLines: aboutRoute ? 1 : 2,
                    maxLines: 4,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: aboutRoute
                          ? l10n.assistantRouteHint
                          : l10n.assistantHint,
                    ),
                    onSubmitted: (_) => unawaited(_send()),
                  ),
                  if (aboutRoute)
                    ..._routeChildren(l10n, theme, advice)
                  else
                    ..._newRouteChildren(l10n, state),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.viewPaddingOf(context).bottom + 16,
              ),
              // The button is locked while it works, so it says what is
              // going on: a line above it would be under the keyboard.
              child: FilledButton.icon(
                onPressed: busy ? null : () => unawaited(_send()),
                icon: busy
                    ? const ButtonProgress()
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  !busy
                      ? l10n.assistantSend
                      : aboutRoute
                      ? (advice.phase == RouteAdvicePhase.reading
                            ? l10n.assistantRouteReading
                            : l10n.assistantThinking)
                      : state.phase == AssistantPhase.asking
                      ? l10n.assistantThinking
                      : l10n.assistantResolving,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Under the field, asking for a new route: examples or wishes, then what
  /// the model understood, the choices to make and the error.
  List<Widget> _newRouteChildren(AppLocalizations l10n, AssistantState state) {
    final wishes = _wishes(l10n);
    return [
      // An empty field gets whole examples; a typed one the wishes the
      // planner acts on, minus those already said.
      if (_empty)
        SectionCaption(l10n.assistantExamples)
      else if (wishes.isNotEmpty)
        SectionCaption(l10n.assistantRefinements),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (_empty)
            for (final example in <String>[
              l10n.assistantExampleFlatLoop,
              l10n.assistantExampleQuietRide,
              l10n.assistantExampleGravel,
            ])
              ActionChip(
                label: Text(example),
                onPressed: () => _prompt.text = example,
              )
          else
            for (final wish in wishes)
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: Text(wish),
                onPressed: state.busy ? null : () => _add(wish),
              ),
        ],
      ),
      if (state.request != null && !state.busy) ...[
        const SizedBox(height: 16),
        _RequestSummary(state: state),
      ],
      if (state.phase == AssistantPhase.needsChoice)
        for (final choice in state.choices)
          _ChoiceRow(
            choice: choice,
            onSelected: (place) => unawaited(_choose(choice.query, place)),
          ),
      if (state.problem != null) ...[
        const SizedBox(height: 16),
        _ProblemRow(
          problem: state.problem!,
          onRetry: ref.read(assistantControllerProvider.notifier).clearProblem,
        ),
      ],
    ];
  }

  /// Under the field, asking about the route on the map: example questions,
  /// or once there is an answer the others to ask next, then the answer,
  /// its findings and the error.
  List<Widget> _routeChildren(
    AppLocalizations l10n,
    ThemeData theme,
    RouteAdviceState advice,
  ) {
    final answer = advice.advice;
    final asked = advice.question.toLowerCase();
    final next = _routeExamples(l10n)
        .where((q) => q.toLowerCase() != asked)
        .toList(growable: false);
    final offered = answer != null
        ? next
        : (_empty ? _routeExamples(l10n) : null);
    final routing = ref.watch(
      plannerControllerProvider.select((s) => s.isRouting),
    );
    return [
      // The answer first, right under the question, where the eye is.
      if (answer != null && !advice.busy) ...[
        const SizedBox(height: 8),
        // What the model wrote is the content here, so it is set in the
        // reading size rather than as a caption.
        Text(answer.answer, style: theme.textTheme.bodyLarge),
        if (answer.findings.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCaption(l10n.assistantRouteFindings),
          for (var i = 0; i < answer.findings.length; i++)
            _FindingRow(
              finding: answer.findings[i],
              place: advice.placeOf(
                answer.findings[i].placeId ?? _stopOf(answer.findings[i]),
              ),
              applied: advice.applied.contains(i),
              // A fix applied meanwhile is still being routed; the next
              // one waits for the route it applies to.
              canApply: !routing,
              onShow: widget.map == null
                  ? null
                  : () => _show(answer.findings[i], advice),
              onApply: () =>
                  ref.read(routeAdviceControllerProvider.notifier).apply(i),
            ),
        ],
      ],
      if (offered != null) ...[
        if (answer != null) const SizedBox(height: 20),
        SectionCaption(
          answer != null
              ? l10n.assistantRouteFollowUps
              : l10n.assistantExamples,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final question in offered)
              ActionChip(
                label: Text(question),
                onPressed: advice.busy
                    ? null
                    : () => _question.value = TextEditingValue(
                        text: question,
                        selection: TextSelection.collapsed(
                          offset: question.length,
                        ),
                      ),
              ),
          ],
        ),
      ],
      if (advice.problem != null) ...[
        const SizedBox(height: 16),
        _ProblemRow(
          problem: advice.problem!,
          onRetry: ref
              .read(routeAdviceControllerProvider.notifier)
              .clearProblem,
        ),
      ],
    ];
  }
}

/// The place an add-stop fix of [finding] names, if it has one.
String? _stopOf(RouteFinding finding) => switch (finding.fix) {
  AddStopFix(:final placeId) => placeId,
  _ => null,
};

/// The icon of a finding of [kind].
IconData _findingIcon(FindingKind kind) => switch (kind) {
  FindingKind.traffic => Icons.directions_car_outlined,
  FindingKind.steep => Icons.trending_up_rounded,
  FindingKind.surface => Icons.texture_rounded,
  FindingKind.water => Icons.water_drop_outlined,
  FindingKind.food => Icons.local_cafe_outlined,
  FindingKind.detour => Icons.alt_route_rounded,
  FindingKind.profile => Icons.directions_bike_rounded,
  FindingKind.other => Icons.info_outline_rounded,
};

/// One finding: what it says, where it is, and what can be done about it.
class _FindingRow extends ConsumerWidget {
  const _FindingRow({
    required this.finding,
    required this.place,
    required this.applied,
    required this.canApply,
    required this.onShow,
    required this.onApply,
  });

  final RouteFinding finding;

  /// The digest place it is about, when it names one.
  final DigestPlace? place;
  final bool applied;
  final bool canApply;
  final VoidCallback? onShow;
  final VoidCallback onApply;

  /// Where along the route it is, in the rider's units.
  String? _where(AppLocalizations l10n, UnitSystem units) {
    String at(double km) => formatDistance(l10n, units, km * 1000);
    final from = finding.fromKm ?? place?.km;
    if (from == null) return null;
    final to = finding.toKm;
    if (to == null || (to - from).abs() < 0.05) {
      return l10n.assistantFindingAt(at(from));
    }
    return l10n.assistantFindingBetween(at(from), at(to));
  }

  String _fixLabel(AppLocalizations l10n, RouteFix fix) => switch (fix) {
    AddStopFix() => l10n.assistantFixAddStop,
    AvoidFix() => l10n.assistantFixAvoid,
    ProfileFix(:final profile) => l10n.assistantFixProfile(
      profileLabel(l10n, RouteProfile.fromName(profile.json)),
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final where = _where(l10n, ref.watch(unitSystemProvider));
    final fix = finding.fix;
    final located =
        place != null || finding.fromKm != null || finding.toKm != null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              _findingIcon(finding.kind),
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(finding.text, style: theme.textTheme.bodyMedium),
                if (where != null)
                  Text(
                    where,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if ((located && onShow != null) || fix != null)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (located && onShow != null)
                        TextButton.icon(
                          onPressed: onShow,
                          icon: const Icon(Icons.visibility_outlined),
                          label: Text(l10n.assistantFindingShow),
                        ),
                      if (fix != null && applied)
                        Chip(
                          avatar: Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          label: Text(l10n.assistantFixApplied),
                        )
                      else if (fix != null)
                        FilledButton.tonal(
                          onPressed: canApply ? onApply : null,
                          child: Text(_fixLabel(l10n, fix)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A spinner the size of a button's icon, for a button that is working.
class ButtonProgress extends StatelessWidget {
  /// Creates the spinner.
  const ButtonProgress({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// What the model asked for, once it is resolved enough to show.
class _RequestSummary extends ConsumerWidget {
  const _RequestSummary({required this.state});

  final AssistantState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final request = state.request!;
    final distance = formatDistance(
      l10n,
      ref.watch(unitSystemProvider),
      request.distanceKm * 1000,
    );
    final places = switch (state.intent) {
      LoopIntent(:final via) => via,
      RouteIntent(:final places) => places,
      _ => const <ResolvedPlace>[],
    };
    final startLabel = switch (state.intent) {
      LoopIntent(:final start) => start?.label,
      RouteIntent(:final waypoints) => waypoints.first.name,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.loop
              ? l10n.assistantSummaryLoop(distance)
              : l10n.assistantSummaryRoute(distance),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          startLabel == null
              ? l10n.assistantStartHere
              : l10n.assistantStartAt(startLabel),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (places.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final place in places)
                Chip(
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: Text(place.label),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The chooser chips for one ambiguous name.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.choice, required this.onSelected});

  final PlaceChoice choice;
  final ValueChanged<ResolvedPlace> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.assistantChoose(choice.query),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in choice.options)
                ActionChip(
                  label: Text(option.label),
                  onPressed: () => onSelected(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The error, with the one action that can help.
class _ProblemRow extends StatelessWidget {
  const _ProblemRow({required this.problem, required this.onRetry});

  final AssistantProblem problem;

  /// Clears the error, keeping what was typed.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: theme.colorScheme.error),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assistantProblemText(l10n, problem),
                style: theme.textTheme.bodyMedium,
              ),
              if (problem.failure == AssistantFailure.notEntitled)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(paywallRoute);
                  },
                  child: Text(l10n.plusSeeDetails),
                )
              else
                TextButton(
                  onPressed: onRetry,
                  child: Text(l10n.assistantRetry),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
