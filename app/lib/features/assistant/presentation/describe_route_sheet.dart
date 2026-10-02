import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/domain/saved_route.dart';
import '../../subscription/application/plus_access.dart';
import '../application/route_description_controller.dart';
import '../data/ai_consent_controller.dart';
import 'ai_consent_dialog.dart';
import 'assistant_sheet.dart' show ButtonProgress, PlusRequiredBanner;
import 'assistant_strings.dart';

/// Opens "Describe this route" for [route].
Future<void> showDescribeRouteSheet(BuildContext context, SavedRoute route) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Over the shell's floating navigation bar, not under it.
      useRootNavigator: true,
      builder: (context) => DescribeRouteSheet(route: route),
    );

/// A sheet that streams a description of a route and offers to keep it.
///
/// The text is not saved until the rider says so: what the model wrote is a
/// suggestion, and an unsaved one costs nothing.
class DescribeRouteSheet extends ConsumerStatefulWidget {
  /// Creates the sheet for [route].
  const DescribeRouteSheet({required this.route, super.key});

  /// The route to describe.
  final SavedRoute route;

  @override
  ConsumerState<DescribeRouteSheet> createState() => _DescribeRouteSheetState();
}

class _DescribeRouteSheetState extends ConsumerState<DescribeRouteSheet> {
  @override
  void initState() {
    super.initState();
    // The rider pressed a button called "Describe this route"; asking them to
    // press another one inside the sheet would be theatre. Known to be
    // without Plus, the sheet says so instead, and writes once Plus is
    // active.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _plusMissing) return;
      unawaited(_run());
    });
  }

  bool get _plusMissing =>
      ref.read(plusAccessProvider(PlusFeature.aiAssistant)) ==
      PlusAccess.missing;

  Future<void> _run() async {
    final consent = ref.read(aiConsentControllerProvider);
    if (consent == null || !consent.allowsRequests) {
      if (!mounted) return;
      final choice = await showAiConsentDialog(context);
      if (choice == null || !mounted) return;
      await ref.read(aiConsentControllerProvider.notifier).set(choice);
      if (!choice.allowsRequests || !mounted) return;
    }
    await ref
        .read(routeDescriptionControllerProvider.notifier)
        .describe(widget.route);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await ref
        .read(routeDescriptionControllerProvider.notifier)
        .save(widget.route);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.describeSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(routeDescriptionControllerProvider);
    final plusMissing =
        ref.watch(plusAccessProvider(PlusFeature.aiAssistant)) ==
        PlusAccess.missing;
    // Back from the paywall subscribed: what the rider asked for.
    ref.listen(plusAccessProvider(PlusFeature.aiAssistant), (before, now) {
      if (before == PlusAccess.missing && now == PlusAccess.granted) {
        unawaited(_run());
      }
    });

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Padding(
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
            Text(l10n.describeTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 14),
            if (state.text.isNotEmpty) ...[
              const SizedBox(height: 10),
              // What the model wrote is the content of this sheet, so it is
              // set in the reading size rather than as a caption.
              Flexible(
                child: SingleChildScrollView(
                  child: Text(state.text, style: theme.textTheme.bodyLarge),
                ),
              ),
            ],
            if (state.problem != null) ...[
              const SizedBox(height: 10),
              Text(
                l10n.describeFailed(assistantProblemText(l10n, state.problem!)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (plusMissing)
              const PlusRequiredBanner()
            else
              Row(
                children: [
                  TextButton(
                    onPressed: state.running ? null : () => unawaited(_run()),
                    child: Text(l10n.describeAgain),
                  ),
                  const SizedBox(width: 12),
                  // Locked while the model writes, so it is where the sheet
                  // says that it does.
                  Expanded(
                    child: state.running
                        ? FilledButton.icon(
                            onPressed: null,
                            icon: const ButtonProgress(),
                            label: Text(l10n.describeRunning),
                          )
                        : FilledButton(
                            onPressed: state.canSave
                                ? () => unawaited(_save())
                                : null,
                            child: Text(l10n.describeSave),
                          ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The route detail's "Describe this route" button.
///
/// Hidden for a route that came from Strava — their API terms do not allow
/// their data to be used for AI. For a rider known to be without Velorki Plus
/// the sheet opens with Subscribe where its buttons would be, and writes
/// once they come back subscribed.
class DescribeRouteButton extends ConsumerWidget {
  /// Creates the button for [route].
  const DescribeRouteButton({required this.route, super.key});

  /// The route to describe.
  final SavedRoute route;

  Future<void> _open(BuildContext context, WidgetRef ref) =>
      showDescribeRouteSheet(context, route);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canDescribe(route)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return OutlinedButton.icon(
      onPressed: () => unawaited(_open(context, ref)),
      icon: const Icon(Icons.auto_awesome),
      label: Text(l10n.describeAction),
    );
  }
}
