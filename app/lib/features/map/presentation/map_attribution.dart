import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/presentation/stat_tile.dart';
import '../data/map_preferences.dart';
import 'map_strings.dart';

/// The attribution required by the OpenStreetMap licence, drawn by us rather
/// than by the native SDK so it survives our own map chrome.
///
/// Tapping it opens a dialog with the full notice; each source opens in the
/// browser, with the address shown as selectable text as a fallback.
class MapAttributionChip extends ConsumerWidget {
  const MapAttributionChip({super.key, this.cyclosmActive});

  /// Overrides the CyclOSM state; by default it follows the overlay toggle.
  final bool? cyclosmActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool cyclosm = cyclosmActive ?? ref.watch(cyclosmOverlayProvider);
    final theme = Theme.of(context);
    final parts = <String>[
      MapStrings.attributionOsm,
      MapStrings.attributionOpenFreeMap,
      if (cyclosm) MapStrings.attributionCyclosm,
    ];
    return Semantics(
      button: true,
      label: MapStrings.attributionTitle,
      child: GlassPanel(
        radius: 999,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () =>
                showMapAttributionDialog(context, cyclosmActive: cyclosm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(parts.join(' · '), style: theme.textTheme.labelSmall),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the full attribution notice with the source URLs.
Future<void> showMapAttributionDialog(
  BuildContext context, {
  required bool cyclosmActive,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(MapStrings.attributionTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(MapStrings.attributionBody),
            const SizedBox(height: 12),
            const _AttributionLink(
              label: MapStrings.attributionOsm,
              url: MapStrings.attributionOsmUrl,
            ),
            const _AttributionLink(
              label: MapStrings.attributionOpenFreeMap,
              url: MapStrings.attributionOpenFreeMapUrl,
            ),
            if (cyclosmActive)
              const _AttributionLink(
                label: MapStrings.attributionCyclosm,
                url: MapStrings.attributionCyclosmUrl,
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(MapStrings.close),
        ),
      ],
    ),
  );
}

class _AttributionLink extends StatelessWidget {
  const _AttributionLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: Text(label, style: theme.textTheme.titleSmall),
          ),
          SelectableText(url, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
