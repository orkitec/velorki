import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/domain/route_poi.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/route_cues.dart';
import 'turn_phrases.dart';

/// The cue sheet of a route being read rather than ridden: every turn and
/// point of interest with its distance from the start, on the import preview
/// and the route page.
///
/// A tap on a line selects it and the owner takes the map there; a tap on a
/// marker on the map selects the line here and scrolls it into view. The
/// selected line opens up with what there is to know: a hazard's note, a
/// turn's plain manoeuvre under the author's words.
class CueSheetList extends ConsumerStatefulWidget {
  /// Creates the list.
  const CueSheetList({
    required this.cues,
    required this.selected,
    required this.onSelect,
    this.collapsedLines = 8,
    super.key,
  });

  /// The route's cues in order.
  final List<RouteCue> cues;

  /// The selected cue's index in [cues], or `null`.
  final int? selected;

  /// A line was tapped.
  final ValueChanged<int> onSelect;

  /// How many lines show before "Show all"; a long route has a hundred.
  final int collapsedLines;

  @override
  ConsumerState<CueSheetList> createState() => _CueSheetListState();
}

class _CueSheetListState extends ConsumerState<CueSheetList> {
  bool _expanded = false;
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(CueSheetList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selected;
    if (selected == null || selected == oldWidget.selected) return;
    // A selection from the map may sit below the fold, or behind "Show all".
    if (selected >= widget.collapsedLines) _expanded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keys[selected]?.currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: const Duration(milliseconds: 250),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final units = ref.watch(unitSystemProvider);
    final cues = widget.cues;
    if (cues.isEmpty) return const SizedBox.shrink();
    final shown = _expanded || cues.length <= widget.collapsedLines
        ? cues.length
        : widget.collapsedLines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(l10n.cueSheetTitle),
        const SizedBox(height: 8),
        for (var i = 0; i < shown; i++)
          _CueLine(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            cue: cues[i],
            distance: formatDistance(l10n, units, cues[i].alongM),
            selected: widget.selected == i,
            onTap: () => widget.onSelect(i),
          ),
        if (shown < cues.length ||
            _expanded && cues.length > widget.collapsedLines)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded
                    ? l10n.cueSheetShowFewer
                    : l10n.cueSheetShowAll(cues.length),
                style: TextStyle(color: scheme.primary),
              ),
            ),
          ),
      ],
    );
  }
}

class _CueLine extends StatelessWidget {
  const _CueLine({
    required this.cue,
    required this.distance,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final RouteCue cue;
  final String distance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.velorki;
    final turn = cue.turn;
    final poi = cue.poi;
    final IconData icon;
    final String label;
    String? detail;
    var tint = scheme.onSurfaceVariant;
    if (poi != null) {
      icon = poiIcon(poi.kind);
      label = poi.name;
      detail = poi.description;
      if (poi.kind == PoiKind.danger) tint = colors.warning;
    } else if (turn != null) {
      icon = cue.isFinish ? Icons.flag : turnIcon(turn.kind);
      label = turnLabel(turn, l10n);
      // The author's words above, the plain manoeuvre underneath.
      if (turn.note != null && turn.note!.isNotEmpty && !cue.isFinish) {
        detail = turnKindLabel(turn, l10n);
      }
    } else {
      return const SizedBox.shrink();
    }
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 20, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                    if (selected && detail != null && detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                distance,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
