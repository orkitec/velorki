import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/place_search_controller.dart';
import '../data/gazetteer_store.dart';
import '../data/photon_client.dart';
import '../domain/search_result.dart';

/// The planner's place search: a text field with a debounced dropdown.
///
/// The widget only reports the chosen place; what happens with it — a new
/// waypoint or a camera move — is the screen's decision.
class SearchField extends ConsumerStatefulWidget {
  /// Creates the search field.
  const SearchField({
    required this.onSelected,
    this.bias,
    this.onCleared,
    this.onFocusChanged,
    super.key,
  });

  /// Called when the field takes or gives up focus, before the keyboard
  /// moves: the screen can make room for it.
  final ValueChanged<bool>? onFocusChanged;

  /// Called when the rider clears the field or edits it after picking a
  /// result: the picked place is no longer what the field says.
  final VoidCallback? onCleared;

  /// Called with the place the user picked.
  final ValueChanged<SearchResult> onSelected;

  /// The current map centre, read when a request goes out.
  final LatLng? Function()? bias;

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  // The results float in the app's overlay, anchored under the field, so
  // nothing on the screen (the planner sheet, for one) can cover them.
  final LayerLink _link = LayerLink();
  final OverlayPortalController _results = OverlayPortalController();
  double _fieldWidth = 0;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  void _onFocus() => widget.onFocusChanged?.call(_focusNode.hasFocus);

  @override
  void dispose() {
    _controller.dispose();
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  bool get _showResults =>
      !_dismissed && _controller.text.trim().length >= searchMinChars;

  void _syncResults() {
    if (_showResults) {
      if (!_results.isShowing) _results.show();
    } else if (_results.isShowing) {
      _results.hide();
    }
  }

  void _onChanged(String text) {
    // Typing over a picked result unpicks it: the pin on the map must not
    // outlive the words that put it there.
    if (_dismissed) widget.onCleared?.call();
    setState(() => _dismissed = false);
    ref
        .read(placeSearchProvider.notifier)
        .query(
          text,
          lang: Localizations.localeOf(context).languageCode,
          bias: widget.bias?.call(),
        );
  }

  void _clear() {
    _controller.clear();
    ref.read(placeSearchProvider.notifier).clear();
    setState(() => _dismissed = false);
    widget.onCleared?.call();
  }

  void _searchOnline() {
    unawaited(
      ref
          .read(placeSearchProvider.notifier)
          .searchOnline(
            lang: Localizations.localeOf(context).languageCode,
            bias: widget.bias?.call(),
          ),
    );
  }

  void _select(SearchResult result) {
    _controller.text = result.name;
    _focusNode.unfocus();
    setState(() => _dismissed = true);
    widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = ref.watch(placeSearchProvider);
    // The field works with a geocoder, with a downloaded gazetteer, or both;
    // only a device with neither has nothing to search.
    final canSearch =
        ref.watch(photonClientProvider) != null ||
        (ref.watch(gazetteerStoreProvider).value?.hasTiles ?? false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncResults();
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        _fieldWidth = constraints.maxWidth;
        return OverlayPortal(
          controller: _results,
          overlayChildBuilder: (context) => Positioned(
            width: _fieldWidth,
            child: CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              showWhenUnlinked: false,
              child: Material(
                type: MaterialType.transparency,
                child: _ResultsCard(
                  results: results,
                  onSelected: _select,
                  onSearchOnline: _searchOnline,
                ),
              ),
            ),
          ),
          child: CompositedTransformTarget(
            link: _link,
            child: GlassPanel(
              radius: 28,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                enabled: canSearch,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: canSearch
                      ? l10n.searchHint
                      : l10n.searchUnavailable,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.searchClear,
                          icon: const Icon(Icons.close),
                          onPressed: _clear,
                        ),
                ),
                onChanged: _onChanged,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({
    required this.results,
    required this.onSelected,
    required this.onSearchOnline,
  });

  final AsyncValue<PlaceSearchState> results;
  final ValueChanged<SearchResult> onSelected;
  final VoidCallback onSearchOnline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      // Opaque: it floats over the chips and the sheet, and a list read
      // through them is not a list.
      child: Material(
        color: scheme.surfaceContainerLowest,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: results.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(
                error is SearchException && error.message.contains('configured')
                    ? l10n.searchUnavailable
                    : l10n.searchFailed,
              ),
              // The reason, so a failure is diagnosable from the screen.
              subtitle:
                  error is SearchException &&
                      !error.message.contains('configured')
                  ? Text(
                      error.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
            ),
            data: (state) => _list(context, state),
          ),
        ),
      ),
    );
  }

  /// The rows: the results, and under them the "search online" row when the
  /// results came off the device and a geocoder is configured.
  ///
  /// The online row is a footer pinned below the scrolling list, not its last
  /// item: it has to be visible whatever the list holds, because it is the
  /// way out when the gazetteer does not know the place.
  Widget _list(BuildContext context, PlaceSearchState state) {
    final l10n = AppLocalizations.of(context);
    final online = state.source == SearchSource.local && state.canSearchOnline;
    final items = state.results;
    final Widget list = items.isEmpty
        ? ListTile(title: Text(l10n.searchNoResults))
        : ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final r = items[i];
              final subtitle = r.source == SearchSource.local
                  ? localResultSubtitle(l10n, r)
                  : r.subtitle;
              return ListTile(
                dense: true,
                leading: Icon(searchResultIcon(r)),
                title: Text(r.name),
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
                onTap: () => onSelected(r),
              );
            },
          );
    if (!online) return list;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: list),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.travel_explore_outlined),
          title: Text(l10n.searchOnlineFor(state.query)),
          onTap: onSearchOnline,
        ),
      ],
    );
  }
}

/// The icon for one result row.
///
/// Online rows keep the neutral pin they always had; a local row says what it
/// is, because the on-device index answers with taps, cafes and peaks next to
/// villages and the kind is what tells them apart at a glance.
IconData searchResultIcon(SearchResult result) {
  if (result.source != SearchSource.local) return Icons.place_outlined;
  return switch (result.kind) {
    SearchKind.place => Icons.location_city_outlined,
    SearchKind.street => Icons.signpost_outlined,
    SearchKind.poi => _poiIcon(result.detail),
    SearchKind.unknown => Icons.place_outlined,
  };
}

IconData _poiIcon(String? detail) => switch (detail) {
  'drinking_water' => Icons.water_drop_outlined,
  'cafe' => Icons.local_cafe_outlined,
  'bicycle_repair_station' => Icons.build_outlined,
  'shelter' => Icons.house_siding_outlined,
  'bicycle_shop' => Icons.pedal_bike_outlined,
  'station' => Icons.train_outlined,
  'viewpoint' => Icons.landscape_outlined,
  'peak' => Icons.terrain_outlined,
  'park' => Icons.park_outlined,
  'attraction' => Icons.attractions_outlined,
  'museum' => Icons.museum_outlined,
  'historic' => Icons.account_balance_outlined,
  'place_of_worship' => Icons.church_outlined,
  'hospital' => Icons.local_hospital_outlined,
  'university' => Icons.school_outlined,
  'stadium' => Icons.stadium_outlined,
  'mall' => Icons.local_mall_outlined,
  'airport' => Icons.flight_outlined,
  'ferry_terminal' => Icons.directions_boat_outlined,
  'tower' => Icons.cell_tower_outlined,
  // Material has no lighthouse; the beam is the closest thing to it.
  'lighthouse' => Icons.lightbulb_outline,
  'water' => Icons.water_outlined,
  'beach' => Icons.beach_access_outlined,
  'nature_reserve' => Icons.forest_outlined,
  'building' => Icons.apartment_outlined,
  _ => Icons.place_outlined,
};

/// The second line of a local row: what it is, and where it is when the
/// gazetteer knows.
String localResultSubtitle(AppLocalizations l10n, SearchResult result) {
  final label = searchKindLabel(l10n, result);
  final where = result.city;
  if (where == null || where.isEmpty) return label;
  return label.isEmpty ? where : '$label \u00b7 $where';
}

/// The localised name of a local result's kind.
String searchKindLabel(AppLocalizations l10n, SearchResult result) {
  if (result.kind == SearchKind.street) return l10n.searchKindStreet;
  return switch (result.detail) {
    'city' => l10n.searchKindCity,
    'town' => l10n.searchKindTown,
    'village' => l10n.searchKindVillage,
    'hamlet' => l10n.searchKindHamlet,
    'suburb' => l10n.searchKindSuburb,
    'neighbourhood' => l10n.searchKindNeighbourhood,
    'locality' => l10n.searchKindLocality,
    'island' => l10n.searchKindIsland,
    'drinking_water' => l10n.searchKindDrinkingWater,
    'cafe' => l10n.searchKindCafe,
    'bicycle_repair_station' => l10n.searchKindBikeRepair,
    'shelter' => l10n.searchKindShelter,
    'bicycle_shop' => l10n.searchKindBikeShop,
    'station' => l10n.searchKindStation,
    'viewpoint' => l10n.searchKindViewpoint,
    'peak' => l10n.searchKindPeak,
    'park' => l10n.searchKindPark,
    'attraction' => l10n.searchKindAttraction,
    'museum' => l10n.searchKindMuseum,
    'historic' => l10n.searchKindHistoric,
    'place_of_worship' => l10n.searchKindWorship,
    'hospital' => l10n.searchKindHospital,
    'university' => l10n.searchKindUniversity,
    'stadium' => l10n.searchKindStadium,
    'mall' => l10n.searchKindMall,
    'airport' => l10n.searchKindAirport,
    'ferry_terminal' => l10n.searchKindFerryTerminal,
    'tower' => l10n.searchKindTower,
    'lighthouse' => l10n.searchKindLighthouse,
    'water' => l10n.searchKindWater,
    'beach' => l10n.searchKindBeach,
    'nature_reserve' => l10n.searchKindNatureReserve,
    'building' => l10n.searchKindBuilding,
    // A landmark the gazetteer classified in a way this build does not know
    // still says it is a place; only a row of another kind stays silent.
    _ => result.kind == SearchKind.poi ? l10n.searchKindPlace : '',
  };
}
