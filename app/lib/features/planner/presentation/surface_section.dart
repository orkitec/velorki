import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/track_surface.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import 'surface_stats_bar.dart';

/// The Surface section of a card whose track had to be matched against the
/// routing tiles: the breakdown once there is one, and what is in the way
/// until then.
///
/// A ride and a route read from a file are the same story — neither went
/// through the router, both are answered by matching the track — so they say
/// the same things in the same words.
class SurfaceSection extends StatelessWidget {
  /// Creates the section for [surface].
  const SurfaceSection({
    required this.surface,
    this.hideWithoutRouting = true,
    super.key,
  });

  /// The matching, in flight or done.
  final AsyncValue<TrackSurface> surface;

  /// Whether a build with no on-device routing leaves the section out
  /// altogether rather than saying there are no figures.
  ///
  /// A ride page drops it: a line about a track that "could not be matched"
  /// would blame the track for a build that was never going to match one.
  /// A route card keeps it, because the card has always had a Surface
  /// section and a section that comes and goes changes the card's height
  /// under the rider — and the card draws the route on the shared map as it
  /// builds, so a height change costs a redraw and a camera fit.
  final bool hideWithoutRouting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget note(String text) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCaption(l10n.surfaceTitle),
        const SizedBox(height: 10),
        Text(text, style: quiet),
      ],
    );

    return surface.when(
      // A write-back re-runs the provider; the answer it then reads off the
      // row is the one already on screen, so no flicker in between.
      skipLoadingOnReload: true,
      // A line rather than a bar: an indeterminate indicator animates for
      // as long as the matching runs, which is a few hundred milliseconds
      // of spinning pixels on a card that is otherwise still, and it never
      // lets a test settle. The words say the same thing.
      loading: () => note(l10n.rideSurfaceComputing),
      error: (_, _) => note(l10n.rideSurfaceUnavailable),
      data: (result) => switch (result.state) {
        TrackSurfaceState.matched => SurfaceStatsBar(stats: result.stats),
        TrackSurfaceState.noTiles => note(l10n.rideSurfaceNoTiles),
        TrackSurfaceState.unmatched => note(l10n.rideSurfaceUnavailable),
        TrackSurfaceState.noRouting =>
          hideWithoutRouting
              ? const SizedBox.shrink()
              : note(l10n.surfaceUnavailable),
      },
    );
  }
}
