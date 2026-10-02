import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/assistant_controller.dart';
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

/// "A hilly 60 km loop from here past the lake", as a text field.
class AssistantSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const AssistantSheet({super.key, this.map});

  /// The planner's map, used to bias the geocoder towards what is on screen.
  final MapController? map;

  @override
  ConsumerState<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends ConsumerState<AssistantSheet> {
  final TextEditingController _prompt = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prompt.text = ref.read(assistantControllerProvider).prompt;
    _empty = _prompt.text.trim().isEmpty;
    // The chips under the field follow what is in it.
    _prompt.addListener(_promptChanged);
  }

  bool _empty = true;

  void _promptChanged() {
    final empty = _prompt.text.trim().isEmpty;
    if (empty != _empty) setState(() => _empty = empty);
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

  Future<void> _choose(String query, ResolvedPlace place) async {
    final position = await requestDevicePosition(context, ref);
    if (!mounted) return;
    await ref
        .read(assistantControllerProvider.notifier)
        .choose(query, place, position: position, bias: widget.map?.center);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(assistantControllerProvider);

    ref.listen(assistantControllerProvider, (previous, next) {
      if (next.phase != AssistantPhase.ready || !mounted) return;
      // Everything that could be done has been done: a loop search is running
      // or the waypoints are on the map. The planner takes it from here.
      Navigator.of(context).pop(next.intent);
    });

    return ConstrainedBox(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.assistantTitle,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  // What leaves the phone and what does not: said in the
                  // reading size, not in fine print.
                  Text(
                    l10n.assistantIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                children: [
                  TextField(
                    controller: _prompt,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(hintText: l10n.assistantHint),
                    onSubmitted: (_) => unawaited(_send()),
                  ),
                  // An empty field gets whole examples; a typed one the
                  // wishes the planner acts on, minus those already said.
                  if (_empty)
                    SectionCaption(l10n.assistantExamples)
                  else if (_wishes(l10n).isNotEmpty)
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
                        for (final wish in _wishes(l10n))
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
                        onSelected: (place) =>
                            unawaited(_choose(choice.query, place)),
                      ),
                  if (state.problem != null) ...[
                    const SizedBox(height: 16),
                    _ProblemRow(problem: state.problem!),
                  ],
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
                onPressed: state.busy ? null : () => unawaited(_send()),
                icon: state.busy
                    ? const ButtonProgress()
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  !state.busy
                      ? l10n.assistantSend
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
class _ProblemRow extends ConsumerWidget {
  const _ProblemRow({required this.problem});

  final AssistantProblem problem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  onPressed: ref
                      .read(assistantControllerProvider.notifier)
                      .clearProblem,
                  child: Text(l10n.assistantRetry),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
