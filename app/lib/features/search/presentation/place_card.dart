import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../map/data/position_provider.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../domain/search_result.dart';
import 'search_field.dart';

/// What the rider chose to do with a picked place on its card.
enum PlaceAction {
  /// Plan from the rider's position to the place.
  routeHere,

  /// Start a new plan at the place.
  startHere,

  /// Put the place into the route where it fits along the way.
  addStop,

  /// Append the place as the new end of the route.
  destination,
}

/// Opens the card of a picked place (a search result, a stop on the map, a
/// place another app sent) on the root navigator, over the navigation bar.
///
/// It names the place, says what and where it is and how far from the rider
/// ([riderPosition] when given, else the device's position) and, when
/// [offRouteM] is given, from the route; [actions] are its buttons, the
/// first one the primary. Answers the action tapped, or `null` when the card
/// was closed without one.
///
/// [onCover] is told how much of the screen's height the card covers, once
/// it is laid out, so the map can keep the place above it.
Future<PlaceAction?> showPlaceCard(
  BuildContext context, {
  required SearchResult place,
  List<PlaceAction> actions = const <PlaceAction>[],
  double? offRouteM,
  LatLng? riderPosition,
  ValueChanged<double>? onCover,
}) => showModalBottomSheet<PlaceAction>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => PlaceCard(
    place: place,
    actions: actions,
    offRouteM: offRouteM,
    riderPosition: riderPosition,
    onCover: onCover,
  ),
);

/// The content of the card [showPlaceCard] opens.
class PlaceCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const PlaceCard({
    required this.place,
    this.actions = const <PlaceAction>[],
    this.offRouteM,
    this.riderPosition,
    this.onCover,
    super.key,
  });

  /// The place the card is about.
  final SearchResult place;

  /// The buttons, the first one the primary; none for a card that only
  /// tells.
  final List<PlaceAction> actions;

  /// How far the place lies off the planned route, when there is one.
  final double? offRouteM;

  /// Where the rider is, when the caller knows better than the device's
  /// position (a ride being recorded).
  final LatLng? riderPosition;

  /// Told the height the card covers, its drag handle included.
  final ValueChanged<double>? onCover;

  @override
  ConsumerState<PlaceCard> createState() => _PlaceCardState();
}

/// The height of the drag handle's strip above the card's content.
const double _dragHandleStrip = kMinInteractiveDimension;

class _PlaceCardState extends ConsumerState<PlaceCard> {
  double? _reported;

  void _report() {
    final onCover = widget.onCover;
    final size = context.size;
    if (onCover == null || size == null) return;
    final cover = size.height + _dragHandleStrip;
    if (_reported != null && (cover - _reported!).abs() < 0.5) return;
    _reported = cover;
    onCover(cover);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final place = widget.place;
    final units = ref.watch(unitSystemProvider);
    final from =
        widget.riderPosition ??
        ref.watch(devicePositionProvider).value?.position;
    // A street picked at a house number already carries the address in its
    // name; anything without a name is called what it is.
    final title = place.name.isNotEmpty
        ? place.name
        : searchResultTitle(l10n, place);
    // The second line the search list shows for the place.
    final subtitle = place.source == SearchSource.local
        ? localResultSubtitle(l10n, place)
        : place.subtitle;
    final offRoute = widget.offRouteM;
    final distances = <String>[
      if (from != null)
        l10n.placeCardFromYou(
          formatDistance(l10n, units, haversineMeters(from, place.position)),
        ),
      if (offRoute != null)
        l10n.placeCardOffRoute(formatDistance(l10n, units, offRoute)),
    ].join(' · ');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report();
    });
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        12,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(searchResultIcon(place), color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: l10n.placeCardClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Padding(
            // Under the title, clear of the close button's column.
            padding: const EdgeInsetsDirectional.only(start: 36, end: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                if (distances.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    distances,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              // Every button as tall as the tallest, when a label wraps.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, action) in widget.actions.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _button(context, action, primary: i == 0),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _button(
    BuildContext context,
    PlaceAction action, {
    required bool primary,
  }) {
    final l10n = AppLocalizations.of(context);
    final (icon, label) = switch (action) {
      PlaceAction.routeHere => (Icons.near_me_rounded, l10n.placeCardRouteHere),
      PlaceAction.startHere => (
        Icons.play_arrow_rounded,
        l10n.plannerSetAsStart,
      ),
      PlaceAction.addStop => (
        Icons.add_location_alt_outlined,
        l10n.placeCardAddStop,
      ),
      PlaceAction.destination => (
        Icons.flag_outlined,
        l10n.placeCardDestination,
      ),
    };
    void onPressed() => Navigator.of(context).pop(action);
    final text = Text(label, textAlign: TextAlign.center);
    return primary
        ? FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: text)
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: text,
          );
  }
}
