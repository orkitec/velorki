import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/links/link_opener.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/data/position_provider.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/button_menu.dart';
import '../../sharing/data/share_service.dart';
import '../data/osm_details.dart';
import '../domain/osm_place_details.dart';
import '../domain/place_links.dart';
import '../domain/search_result.dart';
import 'place_details_view.dart';
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

/// Where the card's "Open in…" menu can take a place.
enum PlaceOpenTarget {
  /// Apple Maps (iOS).
  appleMaps,

  /// The Google Maps app (iOS, when installed).
  googleMaps,

  /// Whatever map app the rider picks from the system's list (Android).
  mapApp,

  /// openstreetmap.org in the browser.
  openStreetMap,

  /// The system share sheet.
  share,
}

/// How far the card has got with the place's OpenStreetMap details.
enum _DetailsPhase { idle, loading, shown, hidden, failed }

/// Opens the card of a picked place (a search result, a stop on the map, a
/// place another app sent) on the root navigator, over the navigation bar.
///
/// It names the place, says what and where it is and how far from the rider
/// ([riderPosition] when given, else the device's position) and, when
/// [offRouteM] is given, from the route; [actions] are its buttons, the
/// first one the primary. Under them, Details (only for a place whose
/// OpenStreetMap element is known; nothing is fetched until it is tapped)
/// and "Open in…". Answers the action tapped, or `null` when the card was
/// closed without one.
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
  _DetailsPhase _phase = _DetailsPhase.idle;
  OsmPlaceDetails? _details;

  /// Whether the Google Maps app is there to open, on iOS; `false` until
  /// the platform has said so.
  bool _googleMaps = false;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(_probeGoogleMaps());
    }
  }

  Future<void> _probeGoogleMaps() async {
    final installed = await ref.read(linkProbeProvider)(googleMapsProbeUri);
    if (mounted && installed) setState(() => _googleMaps = true);
  }

  Future<void> _loadDetails() async {
    final place = widget.place;
    final type = place.osmType;
    final id = place.osmId;
    if (type == null || id == null) return;
    setState(() => _phase = _DetailsPhase.loading);
    try {
      final details = await ref
          .read(osmDetailsSourceProvider)
          .details(type, id);
      if (!mounted) return;
      setState(() {
        _details = details;
        _phase = _DetailsPhase.shown;
      });
    } on Object {
      if (mounted) setState(() => _phase = _DetailsPhase.failed);
    }
  }

  void _onDetails() {
    switch (_phase) {
      case _DetailsPhase.idle || _DetailsPhase.failed:
        unawaited(_loadDetails());
      case _DetailsPhase.shown:
        setState(() => _phase = _DetailsPhase.hidden);
      case _DetailsPhase.hidden:
        setState(() => _phase = _DetailsPhase.shown);
      case _DetailsPhase.loading:
        break;
    }
  }

  /// What the card is called.
  String _title(AppLocalizations l10n) {
    final place = widget.place;
    // A street picked at a house number already carries the address in its
    // name; anything without a name is called what it is.
    return place.name.isNotEmpty ? place.name : searchResultTitle(l10n, place);
  }

  Uri get _osmUri => openStreetMapUri(
    widget.place.position,
    osmType: widget.place.osmType,
    osmId: widget.place.osmId,
  );

  void _open(PlaceOpenTarget target) {
    final l10n = AppLocalizations.of(context);
    final place = widget.place;
    final open = ref.read(linkOpenerProvider);
    final title = _title(l10n);
    switch (target) {
      case PlaceOpenTarget.appleMaps:
        unawaited(open(appleMapsUri(place.position, title)));
      case PlaceOpenTarget.googleMaps:
        unawaited(open(googleMapsUri(place.position)));
      case PlaceOpenTarget.mapApp:
        unawaited(open(geoUri(place.position, title)));
      case PlaceOpenTarget.openStreetMap:
        unawaited(open(_osmUri));
      case PlaceOpenTarget.share:
        unawaited(
          ref.read(textSharerProvider)(
            placeShareText(title, _osmUri),
            subject: title,
          ),
        );
    }
  }

  /// The entries of the "Open in…" menu on this platform.
  List<PlaceOpenTarget> get _targets => <PlaceOpenTarget>[
    if (defaultTargetPlatform == TargetPlatform.iOS) ...[
      PlaceOpenTarget.appleMaps,
      if (_googleMaps) PlaceOpenTarget.googleMaps,
    ] else
      PlaceOpenTarget.mapApp,
    PlaceOpenTarget.openStreetMap,
    PlaceOpenTarget.share,
  ];

  String _targetLabel(AppLocalizations l10n, PlaceOpenTarget target) =>
      switch (target) {
        PlaceOpenTarget.appleMaps => l10n.serviceAppleMaps,
        PlaceOpenTarget.googleMaps => l10n.serviceGoogleMaps,
        PlaceOpenTarget.mapApp => l10n.placeCardOpenInMapApp,
        PlaceOpenTarget.openStreetMap => l10n.serviceOpenStreetMap,
        PlaceOpenTarget.share => l10n.placeCardShare,
      };

  /// Details and "Open in…", side by side.
  Widget _moreRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details = widget.place.hasOsmElement;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Row(
        children: [
          if (details) ...[
            Expanded(
              child: _phase == _DetailsPhase.loading
                  ? const SizedBox(
                      height: 40,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _onDetails,
                      icon: const Icon(Icons.info_outline_rounded),
                      label: Text(l10n.placeCardDetails),
                    ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: ButtonMenu<PlaceOpenTarget>(
              icon: Icons.open_in_new_rounded,
              label: l10n.placeCardOpenIn,
              onSelected: _open,
              entries: [
                for (final target in _targets)
                  PopupMenuItem<PlaceOpenTarget>(
                    value: target,
                    child: Text(_targetLabel(l10n, target)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What came of tapping Details, under the buttons.
  Widget? _detailsBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final details = _details;
    return switch (_phase) {
      _DetailsPhase.shown when details != null => PlaceDetailsView(
        details: details,
      ),
      _DetailsPhase.failed => Padding(
        padding: const EdgeInsetsDirectional.only(start: 36),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.placeDetailsFailed,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_loadDetails()),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
      _ => null,
    };
  }

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
    final title = _title(l10n);
    final detailsBody = _detailsBody(context);
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
          SizedBox(height: widget.actions.isEmpty ? 16 : 8),
          _moreRow(context),
          if (detailsBody != null) ...[const SizedBox(height: 12), detailsBody],
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
