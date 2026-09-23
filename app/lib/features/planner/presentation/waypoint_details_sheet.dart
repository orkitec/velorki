import 'package:flutter/material.dart';

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
}

/// A sheet with a name field, the four kinds to choose from and a note
/// field, pre-filled from [initial]; Save hands the [WaypointDetails] back
/// through the sheet's result, Cancel hands back nothing.
class WaypointDetailsSheet extends StatefulWidget {
  /// Creates the sheet.
  const WaypointDetailsSheet({
    required this.title,
    required this.initial,
    super.key,
  });

  /// The point's name, or its number.
  final String title;

  /// What the point says now.
  final WaypointDetails initial;

  @override
  State<WaypointDetailsSheet> createState() => _WaypointDetailsSheetState();
}

class _WaypointDetailsSheetState extends State<WaypointDetailsSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.name ?? '',
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

  void _save() => Navigator.of(context)
      .pop(WaypointDetails(name: _name.text, poiKind: _kind, note: _note.text));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      // Above the keyboard, which the sheet's own inset does not cover.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.plannerPointName),
            ),
            const SizedBox(height: 16),
            Text(l10n.plannerPointKind, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SegmentedButton<PoiKind>(
              showSelectedIcon: false,
              segments: [
                for (final kind in PoiKind.values)
                  ButtonSegment(
                    value: kind,
                    icon: Icon(poiIcon(kind), size: 18),
                    label: Text(poiKindLabel(l10n, kind)),
                  ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.first),
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
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(l10n.commonSave),
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

/// What [kind] is called in the sheet.
String poiKindLabel(AppLocalizations l10n, PoiKind kind) => switch (kind) {
  PoiKind.danger => l10n.poiKindDanger,
  PoiKind.water => l10n.poiKindWater,
  PoiKind.food => l10n.poiKindFood,
  PoiKind.generic => l10n.poiKindGeneric,
};
