import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart' as format;
import '../../search/domain/search_result.dart';
import '../../search/presentation/search_field.dart'
    show poiKindIcon, gazetteerPoiKindLabel, searchResultTitle;
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../domain/stops_along_route.dart';

/// The next stop of each kind ahead on a guided ride, nearest first: what
/// it is and how far along the route, one tap from being shown on the map.
///
/// Entries share a line where they fit and wrap onto the next where they
/// do not; an entry too long for a line of its own wraps inside itself.
/// Nothing is cut off.
class StopsAheadLine extends ConsumerWidget {
  /// Creates the line.
  const StopsAheadLine({required this.entries, required this.onTap, super.key});

  /// The stops to list, nearest first.
  final List<StopAlongRoute<SearchResult>> entries;

  /// A tap on one of them.
  final ValueChanged<SearchResult> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    return Semantics(
      container: true,
      label: l10n.mapStopsAhead,
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Wrap(
          children: [
            for (final entry in entries)
              InkWell(
                key: ValueKey<String>('stop-ahead-${entry.stop.detail}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => onTap(entry.stop),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        poiKindIcon(entry.stop.detail),
                        size: 16,
                        color: theme.velorki.accent,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          l10n.mapStopAhead(
                            _kindOf(l10n, entry.stop),
                            format.formatDistance(l10n, units, entry.aheadM),
                          ),
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _kindOf(AppLocalizations l10n, SearchResult stop) {
    final kind = stop.detail;
    return (kind == null ? null : gazetteerPoiKindLabel(l10n, kind)) ??
        searchResultTitle(l10n, stop);
  }
}
