import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart' as format;
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/place_search_controller.dart';
import '../data/gazetteer_store.dart';
import '../data/photon_client.dart';
import '../domain/search_kinds.dart';
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
    this.onDownloadArea,
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

  /// Called when the rider taps "Download this area to search offline", which
  /// the list offers while the area under the map centre has no gazetteer.
  ///
  /// The screen decides what that opens — the field knows nothing about
  /// navigation — and leaving it `null` leaves the row out.
  final VoidCallback? onDownloadArea;

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
          keywords: localisedKindKeywords(AppLocalizations.of(context)),
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

  void _searchOffline() {
    unawaited(
      ref
          .read(placeSearchProvider.notifier)
          .searchOffline(
            bias: widget.bias?.call(),
            keywords: localisedKindKeywords(AppLocalizations.of(context)),
          ),
    );
  }

  void _select(SearchResult result) {
    _controller.text = searchResultTitle(AppLocalizations.of(context), result);
    _focusNode.unfocus();
    setState(() => _dismissed = true);
    widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = ref.watch(placeSearchProvider);
    // Read here, not in the overlay's builder: the overlay is built outside
    // this build and a provider may only be watched inside one.
    final units = ref.watch(unitSystemProvider);
    // The field works with a geocoder, with a downloaded gazetteer, or both;
    // only a device with neither has nothing to search.
    final store = ref.watch(gazetteerStoreProvider).value;
    final canSearch =
        ref.watch(photonClientProvider) != null || (store?.hasTiles ?? false);
    // Whether this list can offer the download: there is a map centre, it is
    // not in a downloaded tile, and the screen knows where to send the rider.
    // Read here rather than out of the state, because an errored search
    // (no network) carries no state and is exactly when the row matters.
    final centre = widget.bias?.call();
    final canDownloadHere =
        widget.onDownloadArea != null &&
        centre != null &&
        !(store?.covers(centre) ?? false);

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
                  units: units,
                  canDownloadHere: canDownloadHere,
                  onSelected: _select,
                  onSearchOnline: _searchOnline,
                  onSearchOffline: _searchOffline,
                  onDownloadArea: widget.onDownloadArea,
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
                  // The "no server configured" hint is a sentence, and in
                  // German a longer one than the field is wide: let it wrap
                  // rather than end in an ellipsis.
                  hintMaxLines: canSearch ? 1 : 2,
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

class _ResultsCard extends StatefulWidget {
  const _ResultsCard({
    required this.results,
    required this.units,
    required this.canDownloadHere,
    required this.onSelected,
    required this.onSearchOnline,
    required this.onSearchOffline,
    this.onDownloadArea,
  });

  final AsyncValue<PlaceSearchState> results;
  final UnitSystem units;

  /// Whether the area on screen can be downloaded to be searched offline.
  final bool canDownloadHere;
  final ValueChanged<SearchResult> onSelected;
  final VoidCallback onSearchOnline;
  final VoidCallback onSearchOffline;
  final VoidCallback? onDownloadArea;

  @override
  State<_ResultsCard> createState() => _ResultsCardState();
}

class _ResultsCardState extends State<_ResultsCard> {
  // Owned here so the scrollbar can stay visible: a list that is longer
  // than the card must look longer than the card.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
          // About five rows and the footer; more than that scrolls, visibly.
          constraints: const BoxConstraints(maxHeight: 380),
          child: widget.results.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            // A search that failed with no gazetteer under the map centre is
            // the moment the download matters most, so the row stays under
            // the error as well.
            error: (error, _) => _withFooter(
              context,
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(
                  error is SearchException &&
                          error.message.contains('configured')
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
            ),
            data: (state) => _list(context, state),
          ),
        ),
      ),
    );
  }

  /// The rows: the results, and under them the one row that leads out of what
  /// is on screen — "Search online for …" below local results, "Show offline
  /// results" below online ones where the area is downloaded, and "Download
  /// this area to search offline" where it is not.
  ///
  /// That row is a footer pinned below the scrolling list, not its last item:
  /// it has to be visible whatever the list holds, because it is the way out
  /// when what answered does not know the place.
  Widget _list(BuildContext context, PlaceSearchState state) {
    final l10n = AppLocalizations.of(context);
    final online = state.source == SearchSource.local && state.canSearchOnline;
    final offline =
        state.source == SearchSource.online && state.offlineAvailableHere;
    final items = state.results;
    final corrected = state.correctedQuery;
    final Widget list = items.isEmpty
        ? ListTile(title: Text(l10n.searchNoResults))
        : Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final r = items[i];
                final subtitle = r.source == SearchSource.local
                    ? localResultSubtitle(l10n, r, units: widget.units)
                    : r.subtitle;
                return ListTile(
                  dense: true,
                  leading: Icon(searchResultIcon(r)),
                  title: Text(searchResultTitle(l10n, r)),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  onTap: () => widget.onSelected(r),
                );
              },
            ),
          );
    final footer = online
        ? ListTile(
            dense: true,
            leading: const Icon(Icons.travel_explore_outlined),
            title: Text(l10n.searchOnlineFor(state.query)),
            onTap: widget.onSearchOnline,
          )
        : offline
        ? ListTile(
            dense: true,
            leading: const Icon(Icons.offline_pin_outlined),
            title: Text(l10n.searchShowOffline),
            onTap: widget.onSearchOffline,
          )
        : _downloadRow(context);
    if (footer == null && corrected == null) return list;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // What the index was actually asked, when it was not what was typed.
        if (corrected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text(
              l10n.searchCorrectedTo(corrected),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Flexible(child: list),
        if (footer != null) ...[const Divider(height: 1), footer],
      ],
    );
  }

  /// [child] with the download row pinned under it, where there is one.
  Widget _withFooter(BuildContext context, Widget child) {
    final row = _downloadRow(context);
    if (row == null) return child;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: child),
        const Divider(height: 1),
        row,
      ],
    );
  }

  /// "Download this area to search offline", or `null` when the area under
  /// the map centre is downloaded already (or there is no centre to judge).
  Widget? _downloadRow(BuildContext context) {
    final onDownload = widget.onDownloadArea;
    if (!widget.canDownloadHere || onDownload == null) return null;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.download_outlined),
      title: Text(AppLocalizations.of(context).searchDownloadAreaOffline),
      onTap: onDownload,
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
    SearchKind.place => _placeIcon(result.detail),
    SearchKind.street => Icons.signpost_outlined,
    SearchKind.poi => _poiIcon(result.detail),
    SearchKind.unknown => Icons.place_outlined,
  };
}

/// A settlement's icon shrinks with the settlement, so a city and the hamlet
/// that shares its name are told apart at a glance.
IconData _placeIcon(String? detail) => switch (detail) {
  'city' => Icons.location_city_outlined,
  'town' => Icons.domain_outlined,
  'village' => Icons.cottage_outlined,
  'hamlet' => Icons.house_outlined,
  'suburb' || 'neighbourhood' => Icons.maps_home_work_outlined,
  'locality' => Icons.pin_drop_outlined,
  'island' => Icons.waves_outlined,
  _ => Icons.location_city_outlined,
};

IconData _poiIcon(String? detail) => switch (detail) {
  'drinking_water' => Icons.water_drop_outlined,
  'toilets' => Icons.wc_outlined,
  'bicycle_rental' => Icons.directions_bike_outlined,
  'charging_station' => Icons.ev_station_outlined,
  'pharmacy' => Icons.local_pharmacy_outlined,
  'picnic_site' => Icons.deck_outlined,
  'bicycle_parking' => Icons.local_parking_outlined,
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
  'mountain_pass' => Icons.hiking,
  'camp_site' => Icons.holiday_village_outlined,
  'hotel' => Icons.hotel_outlined,
  'hostel' => Icons.bed_outlined,
  'alpine_hut' => Icons.cabin_outlined,
  'supermarket' => Icons.shopping_cart_outlined,
  'bakery' => Icons.bakery_dining_outlined,
  _ => Icons.place_outlined,
};

/// The first line of a result row.
///
/// The gazetteer stores unnamed taps, toilets, shelters and bike parkings \u2014
/// there is nothing to call them and nothing to find them by name \u2014 so a row
/// with no name is titled with what it is. This is the one place that
/// substitution happens: [SearchResult.name] stays empty everywhere else.
String searchResultTitle(AppLocalizations l10n, SearchResult result) {
  if (result.name.isNotEmpty) return result.name;
  final label = searchKindLabel(l10n, result);
  return label.isEmpty ? l10n.searchKindPlace : label;
}

/// The second line of a local row: what it is, how far away when it was found
/// by its kind, the house number when the rider typed one, and where it is
/// when the gazetteer knows.
///
/// "Street \u00b7 400 \u00b7 Manhattan", and "Street \u00b7 \u2248 400 \u00b7 Manhattan" when the
/// number sits between the ones the gazetteer knows rather than on one of
/// them; "Drinking water \u00b7 350 m" for the nearest tap, in [units]. Every part
/// is optional; the separator is put in once, here.
String localResultSubtitle(
  AppLocalizations l10n,
  SearchResult result, {
  UnitSystem? units,
}) {
  final number = result.houseNumber;
  final meters = result.distanceMeters;
  return <String>[
    // An unnamed row already shows its kind as the title.
    if (result.name.isNotEmpty) searchKindLabel(l10n, result),
    if (meters != null && units != null)
      format.formatDistance(l10n, units, meters),
    if (number != null && number.isNotEmpty)
      result.approximate ? l10n.searchApproximateNumber(number) : number,
    result.city ?? '',
  ].where((part) => part.isNotEmpty).join(' \u00b7 ');
}

/// Every kind's localised label, lower case, mapped to the kind: the table the
/// store matches a typed "drinking water" or "Trinkwasser" against.
///
/// Built once per language \u2014 the labels do not change while the app runs, and
/// this is asked for on every keystroke.
Map<String, String> localisedKindKeywords(AppLocalizations l10n) =>
    _keywordCache.putIfAbsent(l10n.localeName, () {
      final table = <String, String>{};
      for (final kind in searchPoiKinds) {
        final label = searchKindLabel(
          l10n,
          SearchResult(
            name: '',
            position: const LatLng(0, 0),
            source: SearchSource.local,
            kind: SearchKind.poi,
            detail: kind,
          ),
        );
        // The fallback label ("Place") names no kind in particular.
        if (label.isEmpty || label == l10n.searchKindPlace) continue;
        table.putIfAbsent(label.toLowerCase(), () => kind);
      }
      return table;
    });

final Map<String, Map<String, String>> _keywordCache =
    <String, Map<String, String>>{};

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
    'toilets' => l10n.searchKindToilets,
    'bicycle_rental' => l10n.searchKindBikeRental,
    'charging_station' => l10n.searchKindCharging,
    'pharmacy' => l10n.searchKindPharmacy,
    'picnic_site' => l10n.searchKindPicnicSite,
    'bicycle_parking' => l10n.searchKindBikeParking,
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
    'mountain_pass' => l10n.searchKindMountainPass,
    'camp_site' => l10n.searchKindCampSite,
    'hotel' => l10n.searchKindHotel,
    'hostel' => l10n.searchKindHostel,
    'alpine_hut' => l10n.searchKindAlpineHut,
    'supermarket' => l10n.searchKindSupermarket,
    'bakery' => l10n.searchKindBakery,
    // A landmark the gazetteer classified in a way this build does not know
    // still says it is a place; only a row of another kind stays silent.
    _ => result.kind == SearchKind.poi ? l10n.searchKindPlace : '',
  };
}
