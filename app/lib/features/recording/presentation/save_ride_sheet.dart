import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/ride_stats.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import 'recording_format.dart';

/// What the rider decided about the ride they have just finished.
sealed class SaveRideOutcome {
  const SaveRideOutcome();
}

/// Keep the ride, under [name].
final class SaveRide extends SaveRideOutcome {
  /// Creates the outcome.
  const SaveRide(this.name);

  /// The name the rider left in the field, never empty.
  final String name;
}

/// Throw the ride away.
final class DiscardRide extends SaveRideOutcome {
  /// Creates the outcome.
  const DiscardRide();
}

/// Carry on recording: the stop was a mistake.
final class ContinueRide extends SaveRideOutcome {
  /// Creates the outcome.
  const ContinueRide();
}

/// Asks the rider what the ride they have just stopped is called.
///
/// The sheet cannot be dismissed — no swipe, no barrier tap — because a ride
/// that is neither saved nor discarded nor carried on is a ride left
/// half-finished. The three buttons are the only ways out, and the back
/// button is the mildest of them: it continues the ride, because a stop hit
/// by accident and then backed out of should not finish anything.
Future<SaveRideOutcome> showSaveRideSheet(
  BuildContext context, {
  required String defaultName,
  required RideStats stats,
}) async {
  final outcome = await showModalBottomSheet<SaveRideOutcome>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    // The shell's floating navigation bar belongs to the branch navigator, so
    // a sheet opened there would sit under it.
    useRootNavigator: true,
    builder: (context) => SaveRideSheet(defaultName: defaultName, stats: stats),
  );
  // Nothing but the buttons can close it, but a route that is torn down with
  // the screen must not decide anything: the recording is paused with its
  // journal on disk, and carrying on loses nothing.
  return outcome ?? const ContinueRide();
}

/// The body of [showSaveRideSheet].
class SaveRideSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const SaveRideSheet({
    required this.defaultName,
    required this.stats,
    super.key,
  });

  /// The name the field starts with, and the one an empty field falls back to.
  final String defaultName;

  /// What was recorded, for the figures above the buttons.
  final RideStats stats;

  @override
  ConsumerState<SaveRideSheet> createState() => _SaveRideSheetState();
}

class _SaveRideSheetState extends ConsumerState<SaveRideSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.defaultName)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.defaultName.length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The name the rider left behind; an emptied field means they did not want
  /// to name it, not that the ride has no name.
  String get _name {
    final typed = _controller.text.trim();
    return typed.isEmpty ? widget.defaultName : typed;
  }

  void _save() => Navigator.of(context).pop(SaveRide(_name));

  void _continue() => Navigator.of(context).pop(const ContinueRide());

  Future<void> _discard() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.rideSaveDiscardTitle),
        content: Text(l10n.rideSaveDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.rideSaveDiscard),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && mounted) {
      navigator.pop(const DiscardRide());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final stats = widget.stats;
    return PopScope<SaveRideOutcome>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _continue();
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.rideSaveTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.rideSaveNameLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            StatRow(
              children: [
                StatTile(
                  label: l10n.statDistance,
                  value: formatDistance(l10n, units, stats.distanceM),
                  size: StatSize.medium,
                ),
                StatTile(
                  label: l10n.statMovingTime,
                  value: formatClock(stats.movingTime),
                  size: StatSize.medium,
                ),
                StatTile(
                  label: l10n.statAscent,
                  value: formatHeight(l10n, units, stats.ascentM),
                  size: StatSize.medium,
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Saving is what almost every stop means, so it is the one wide
            // button; carrying on and throwing away share the row below it.
            FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _continue,
                    child: Text(
                      l10n.rideSaveContinue,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: _discard,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text(
                      l10n.rideSaveDiscard,
                      textAlign: TextAlign.center,
                    ),
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
