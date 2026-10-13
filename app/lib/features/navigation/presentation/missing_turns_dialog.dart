import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../planner/domain/saved_route.dart';
import '../../routing_tiles/application/tile_download_controller.dart';
import '../../routing_tiles/presentation/routing_tiles_screen.dart';
import '../application/route_turn_generator.dart';

/// Before a ride on [route]: when it has no turn instructions, asks whether
/// to make them from the map, makes them, and says whether the ride may
/// start. `false` when the rider backed out.
///
/// "Create" first offers the download of the route's region when its tiles
/// are not on the phone, the screen the planner offers for a route it
/// cannot work out, and carries on once the rider is back from it.
Future<bool> confirmRouteTurns(
  BuildContext context,
  WidgetRef ref,
  SavedRoute route,
) async {
  if (!RouteTurnGenerator.needsTurns(route)) return true;
  final l10n = AppLocalizations.of(context);
  final create = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // Scrolls, so it fits a phone turned sideways.
      scrollable: true,
      title: Text(l10n.turnsMissingTitle),
      content: Text(l10n.turnsMissingBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.turnsMissingRideWithout),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.turnsMissingCreate),
        ),
      ],
    ),
  );
  if (create == null || !context.mounted) return false;
  if (!create) return true;

  final missing = ref.read(routeTurnGeneratorProvider).missingTiles(route);
  if (missing != null && missing.isNotEmpty) {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutingTilesScreen(preselected: missing),
      ),
    );
    if (!context.mounted) return false;
  }

  final outcome = await showDialog<RouteTurnsOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreatingTurnsDialog(route: route),
  );
  if (!context.mounted) return false;
  if (outcome == RouteTurnsOutcome.created) return true;

  final ride = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(l10n.turnsMissingTitle),
      content: Text(
        outcome == RouteTurnsOutcome.noTiles
            ? l10n.turnsCreateNoRegion
            : l10n.turnsCreateFailed,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.turnsMissingRideWithout),
        ),
      ],
    ),
  );
  return ride ?? false;
}

/// The wait while the turns are made: first for a download the rider
/// started, then for the router. Closes itself with the outcome.
class _CreatingTurnsDialog extends ConsumerStatefulWidget {
  const _CreatingTurnsDialog({required this.route});

  final SavedRoute route;

  @override
  ConsumerState<_CreatingTurnsDialog> createState() =>
      _CreatingTurnsDialogState();
}

class _CreatingTurnsDialogState extends ConsumerState<_CreatingTurnsDialog> {
  bool _downloading = false;
  late final RouteTurnGenerator _generator = ref.read(
    routeTurnGeneratorProvider,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final outcome = await _make();
    if (mounted) Navigator.of(context).pop(outcome);
  }

  Future<RouteTurnsOutcome> _make() async {
    // A download the rider started on the tiles screen is waited for.
    var waited = false;
    while (ref.read(tileDownloadQueueProvider).isRunning) {
      if (!_downloading) setState(() => _downloading = true);
      waited = true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return RouteTurnsOutcome.noTiles;
    }
    var missing = _generator.missingTiles(widget.route);
    // A tile that has just arrived takes a moment to be counted.
    for (var i = 0; waited && i < 4 && (missing?.isNotEmpty ?? false); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return RouteTurnsOutcome.noTiles;
      missing = _generator.missingTiles(widget.route);
    }
    if (missing == null) return RouteTurnsOutcome.noRouting;
    if (missing.isNotEmpty) return RouteTurnsOutcome.noTiles;
    try {
      final job = _generator.generate(widget.route);
      // The bar follows the job from here.
      setState(() => _downloading = false);
      return await job;
    } on Object {
      return RouteTurnsOutcome.unmatched;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _downloading ? l10n.turnsWaitingForDownload : l10n.turnsCreating,
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<double?>(
            valueListenable: _generator.progressOf(widget.route.id),
            builder: (context, progress, _) =>
                LinearProgressIndicator(value: _downloading ? null : progress),
          ),
        ],
      ),
    );
  }
}
