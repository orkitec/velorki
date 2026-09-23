import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../domain/route_poi.dart';

/// What a rider can say about a waypoint: a name, a kind and a note.
class WaypointDetails {
  /// Creates the details.
  const WaypointDetails({this.name, this.poiKind = PoiKind.generic, this.note});

  /// The name, or `null` for none.
  final String? name;

  /// What the point is about.
  final PoiKind poiKind;

  /// The note, or `null` for none.
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is WaypointDetails &&
      other.name == name &&
      other.poiKind == poiKind &&
      other.note == note;

  @override
  int get hashCode => Object.hash(name, poiKind, note);
}

/// How the edit sheet closed: with details to apply, or with the point to
/// be removed. [index] is where the point is by then, since the sheet moves
/// it in the order while it is open.
sealed class WaypointEditResult {
  const WaypointEditResult(this.index);

  /// The point's index when the sheet closed.
  final int index;
}

/// Done: [details] for the point at [index].
class WaypointEditDone extends WaypointEditResult {
  /// Creates the result.
  const WaypointEditDone(super.index, this.details);

  /// What the rider typed and chose.
  final WaypointDetails details;
}

/// Remove: the point at [index] goes.
class WaypointEditRemove extends WaypointEditResult {
  /// Creates the result.
  const WaypointEditRemove(super.index);
}

/// The one sheet a tapped marker opens: name, kind and note above the row
/// that moves the point in the order, Remove, and Done.
///
/// Name, kind and note are handed back in the sheet's result when it closes
/// with Done; earlier and later go through [onSwap] at once and leave the
/// sheet open, so a point can be moved and named in one visit. A pull down
/// or a tap outside cancels the typing, the swaps stay.
class WaypointEditSheet extends StatefulWidget {
  /// Creates the sheet for the point at [index] of [count].
  const WaypointEditSheet({
    required this.index,
    required this.count,
    required this.initial,
    required this.onSwap,
    super.key,
  });

  /// Where the point is in the order when the sheet opens.
  final int index;

  /// How many points the plan has.
  final int count;

  /// What the point says now.
  final WaypointDetails initial;

  /// Swaps the point at the first argument with the one the second argument
  /// places away, -1 or +1.
  final void Function(int index, int offset) onSwap;

  @override
  State<WaypointEditSheet> createState() => _WaypointEditSheetState();
}

class _WaypointEditSheetState extends State<WaypointEditSheet> {
  late int _index = widget.index;

  /// The number the name field opens with when the point has no name: a
  /// field that shows what the marker shows, rather than an empty one under
  /// a "Point 6" title.
  late final String _number = '${widget.index + 1}';
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.name ?? _number,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.initial.note ?? '',
  );
  late PoiKind _kind = widget.initial.poiKind;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The name as the plan stores it: blank is none, and so is the point's
  /// own number, the one the field opened with or the one it has after a
  /// swap, so leaving the field alone names nothing.
  String? _nameOrNone() {
    final text = _name.text.trim();
    if (text.isEmpty || text == _number || text == '${_index + 1}') {
      return null;
    }
    return text;
  }

  void _done() => Navigator.of(context).pop(
    WaypointEditDone(
      _index,
      WaypointDetails(
        name: _nameOrNone(),
        poiKind: _kind,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    ),
  );

  void _swap(int offset) {
    widget.onSwap(_index, offset);
    setState(() => _index += offset);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      // Above the keyboard, which the sheet's own inset does not cover.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.plannerPointName),
            ),
            const SizedBox(height: 16),
            Text(l10n.plannerPointKind, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            PoiKindTiles(
              selected: _kind,
              onSelected: (kind) => setState(() => _kind = kind),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.plannerPointNote,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            // Reordering by one place at a time: swap with a neighbour.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _index > 0 ? () => _swap(-1) : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    label: Text(l10n.plannerVisitEarlier),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _index < widget.count - 1
                        ? () => _swap(1)
                        : null,
                    icon: const Icon(Icons.arrow_downward_rounded),
                    label: Text(l10n.plannerVisitLater),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () =>
                  Navigator.of(context).pop(WaypointEditRemove(_index)),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l10n.plannerRemovePoint),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: primaryButtonHeight,
              child: FilledButton(
                onPressed: _done,
                child: Text(l10n.commonDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four kinds as equal tiles across the sheet, icon over a one-line
/// label, the chosen one filled with the scheme's primary.
///
/// Tiles rather than a segmented button: four icon-beside-label segments
/// did not fit a phone's width, and every label broke onto a second line.
class PoiKindTiles extends StatelessWidget {
  /// Creates the tiles with [selected] filled.
  const PoiKindTiles({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The kind chosen now.
  final PoiKind selected;

  /// Called with the kind a tap chose.
  final ValueChanged<PoiKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return Row(
      children: [
        for (final (i, kind) in PoiKind.values.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              selected: kind == selected,
              child: Material(
                // Fill and text from the one scheme, so they agree in both
                // themes: a tint of the accent under white text did not.
                color: kind == selected
                    ? scheme.primary
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(kind),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          poiIcon(kind),
                          size: 22,
                          color: kind == selected
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 4),
                        // One line whatever the language: a label longer
                        // than its quarter shrinks rather than wrapping or
                        // ending in an ellipsis.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            poiKindLabel(l10n, kind),
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: labelStyle?.copyWith(
                              color: kind == selected
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// What [kind] is called in the sheet.
String poiKindLabel(AppLocalizations l10n, PoiKind kind) => switch (kind) {
  PoiKind.danger => l10n.poiKindDanger,
  PoiKind.water => l10n.poiKindWater,
  PoiKind.food => l10n.poiKindFood,
  PoiKind.generic => l10n.poiKindGeneric,
};
