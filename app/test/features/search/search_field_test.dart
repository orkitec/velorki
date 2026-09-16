import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/units/units.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki/l10n/generated/app_localizations_en.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/pump.dart';
import 'support/fake_http.dart';
import 'support/gazetteer_fixture.dart';

/// A map centre inside `E5_N45`, the tile the fixture gazetteer covers.
const LatLng inTheTile = LatLng(47.1410, 9.5209);

/// A map centre in `E10_N45`, which no gazetteer here covers.
const LatLng outsideTheTile = LatLng(48.1374, 11.5755);

void main() {
  group('kinds, icons and labels', _kindTable);

  testWidgets('nothing is sent below three characters', (tester) async {
    final h = await pumpScreen(
      tester,
      Scaffold(body: SearchField(onSelected: (_) {})),
    );

    await tester.enterText(find.byType(TextField), 'mu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(h.photonAdapter.requests, isEmpty);
  });

  testWidgets('three characters search after the debounce, once', (
    tester,
  ) async {
    final selected = <SearchResult>[];
    final h = await pumpScreen(
      tester,
      Scaffold(body: SearchField(onSelected: selected.add)),
    );

    await tester.enterText(find.byType(TextField), 'mun');
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.photonAdapter.requests, isEmpty);

    await tester.enterText(find.byType(TextField), 'munich');
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.photonAdapter.requests, isEmpty);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(h.photonAdapter.requests, hasLength(1));
    expect(h.photonAdapter.lastUri.queryParameters['q'], 'munich');
    expect(h.photonAdapter.lastUri.queryParameters['lang'], 'en');
    expect(find.text('Munich'), findsOneWidget);
    expect(find.text('Cafe Kosmos'), findsOneWidget);

    await tester.tap(find.text('Cafe Kosmos'));
    await tester.pumpAndSettle();

    expect(selected.single.name, 'Cafe Kosmos');
    // The list collapses once a place was chosen.
    expect(find.text('Munich'), findsNothing);
  });

  testWidgets('an empty answer says so and clearing resets the field', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Scaffold(body: SearchField(onSelected: (_) {})),
      harness: PlannerHarness(
        photonBody: '{"type":"FeatureCollection","features":[]}',
      ),
    );

    await tester.enterText(find.byType(TextField), 'nowhere');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Nothing found.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Nothing found.'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('without a geocoder the field is disabled', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(body: SearchField(onSelected: (_) {})),
      harness: PlannerHarness(withGeocoder: false),
    );

    expect(
      find.text('No search server configured, set one in Settings → Advanced.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  group('with a gazetteer on the device', () {
    late Directory dir;

    setUp(() {
      final root = Directory.systemTemp.createTempSync('velorki-field');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      dir = Directory('${root.path}/gazetteer')..createSync(recursive: true);
    });

    /// The store override, over a fixture unless [empty].
    List<Override> storeOverride({
      bool empty = false,
      List<GazPoi> extraPois = const <GazPoi>[],
    }) {
      if (!empty) {
        buildGazetteer(
          dir,
          'E5_N45',
          places: fixturePlaces,
          streets: fixtureStreets,
          pois: <GazPoi>[...fixturePois, ...extraPois],
          // Städtle 2 and 10 are known, so 2 is exact and 4 is interpolated.
          houseNumbers: const <GazHouseNumber>[
            GazHouseNumber(11, 2, 47.1398, 9.5210),
            GazHouseNumber(11, 10, 47.1404, 9.5222),
          ],
        );
      }
      final store = GazetteerStore(dir);
      addTearDown(store.close);
      return <Override>[
        gazetteerStoreProvider.overrideWith((ref) async {
          await store.refresh();
          return store;
        }),
      ];
    }

    Future<PlannerHarness> pumpField(
      WidgetTester tester, {
      bool empty = false,
      bool withGeocoder = true,
      String text = 'vaduz',
      // The map is over the tile the fixture covers unless a test says
      // otherwise: that is what makes the search a local one.
      LatLng? bias = inTheTile,
      List<GazPoi> extraPois = const <GazPoi>[],
      VoidCallback? onDownloadArea,
      String photonBody = photonFixture,
    }) async {
      final h = await pumpScreen(
        tester,
        Scaffold(
          body: SearchField(
            onSelected: (_) {},
            bias: () => bias,
            onDownloadArea: onDownloadArea,
          ),
        ),
        harness: PlannerHarness(
          withGeocoder: withGeocoder,
          photonBody: photonBody,
        ),
        extraOverrides: storeOverride(empty: empty, extraPois: extraPois),
      );
      // The store is opened while the app starts; a frame stands in for that.
      await tester.pump();
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('local rows say what they are and stay off the network', (
      tester,
    ) async {
      final h = await pumpField(tester);

      expect(h.photonAdapter.requests, isEmpty);
      expect(find.text('Vaduz'), findsOneWidget);
      expect(find.byIcon(Icons.domain_outlined), findsWidgets);
      expect(find.text('Town'), findsOneWidget);
    });

    testWidgets('a village names its town, a POI its kind', (tester) async {
      await pumpField(tester, text: 'muhleholz');

      expect(find.text('Village \u00b7 Vaduz'), findsOneWidget);
      expect(find.text('Drinking water \u00b7 Mühleholz'), findsOneWidget);
      expect(find.byIcon(Icons.water_drop_outlined), findsOneWidget);
    });

    testWidgets('a street row carries the signpost icon', (tester) async {
      await pumpField(tester, text: 'im muhl');

      expect(find.text('Im Mühleholz'), findsOneWidget);
      expect(find.text('Street \u00b7 Vaduz'), findsOneWidget);
      expect(find.byIcon(Icons.signpost_outlined), findsOneWidget);
    });

    testWidgets('a house number typed with the street shows up in the row', (
      tester,
    ) async {
      await pumpField(tester, text: 'stadtle 2');

      expect(find.text('Städtle'), findsOneWidget);
      expect(find.text('Street \u00b7 2 \u00b7 Vaduz'), findsOneWidget);
    });

    testWidgets('a number between the known ones is marked approximate', (
      tester,
    ) async {
      await pumpField(tester, text: 'stadtle 4');

      expect(find.text('Street \u00b7 \u2248 4 \u00b7 Vaduz'), findsOneWidget);
    });

    testWidgets('a kind word lists the nearest ones, unnamed rows included', (
      tester,
    ) async {
      await pumpField(
        tester,
        text: 'drinking water',
        bias: const LatLng(47.1410, 9.5209),
        extraPois: const <GazPoi>[
          GazPoi.unnamed(30, 'drinking_water', 47.1415, 9.5209),
        ],
      );

      // The unnamed tap is the nearest and wears its kind as its name.
      final rows = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title! as Text).data)
          .toList();
      expect(rows.first, 'Drinking water');
      expect(rows[1], 'Brunnen Mühleholz');
      expect(find.byIcon(Icons.water_drop_outlined), findsNWidgets(2));
      expect(find.textContaining(RegExp(r'^5\d m')), findsOneWidget);
      expect(
        find.textContaining('Drinking water \u00b7 7'),
        findsOneWidget,
        reason: 'the named tap is some 760 m from the centre',
      );
    });

    testWidgets('a misspelling is corrected and the card says so', (
      tester,
    ) async {
      await pumpField(tester, text: 'vaduzz');

      expect(
        find.text('Showing results for \u201cvaduz\u201d'),
        findsOneWidget,
      );
      expect(find.text('Vaduz'), findsOneWidget);
    });

    testWidgets('a query that answers is never corrected', (tester) async {
      await pumpField(tester);

      expect(find.textContaining('Showing results for'), findsNothing);
    });

    testWidgets('the last row offers the online search and runs it', (
      tester,
    ) async {
      final h = await pumpField(tester);
      final online = find.text('Search online for \u201cvaduz\u201d');

      expect(online, findsOneWidget);
      expect(find.byIcon(Icons.travel_explore_outlined), findsOneWidget);

      await tester.tap(online);
      await tester.pumpAndSettle();

      expect(h.photonAdapter.requests, hasLength(1));
      expect(h.photonAdapter.lastUri.queryParameters['q'], 'vaduz');
      expect(find.text('Munich'), findsOneWidget);
      expect(online, findsNothing, reason: 'the results are online now');
    });

    testWidgets('nothing found still offers the online search', (tester) async {
      final h = await pumpField(tester, text: 'atlantis');

      expect(find.text('Nothing found.'), findsOneWidget);
      expect(
        find.text('Search online for \u201catlantis\u201d'),
        findsOneWidget,
      );
      expect(h.photonAdapter.requests, isEmpty);
    });

    testWidgets('without a geocoder there is no online row', (tester) async {
      await pumpField(tester, withGeocoder: false);

      expect(find.text('Vaduz'), findsOneWidget);
      expect(find.byIcon(Icons.travel_explore_outlined), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).enabled,
        isTrue,
        reason: 'the gazetteer alone is enough to search',
      );
    });

    testWidgets('a centre outside the downloaded area offers the download', (
      tester,
    ) async {
      var taps = 0;
      final h = await pumpField(
        tester,
        text: 'munich',
        bias: outsideTheTile,
        onDownloadArea: () => taps++,
      );

      expect(
        h.photonAdapter.requests,
        hasLength(1),
        reason: 'the gazetteer knows nothing about this area',
      );
      expect(find.text('Munich'), findsOneWidget);
      final row = find.text('Download this area to search offline');
      expect(row, findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(
        find.text('Show offline results'),
        findsNothing,
        reason: 'there is nothing offline to show here',
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('over a downloaded area there is nothing to download', (
      tester,
    ) async {
      await pumpField(tester, onDownloadArea: () {});

      expect(find.text('Vaduz'), findsOneWidget);
      expect(find.text('Download this area to search offline'), findsNothing);
      expect(find.text('Search online for \u201cvaduz\u201d'), findsOneWidget);
    });

    testWidgets('without a map centre the download row stays away', (
      tester,
    ) async {
      await pumpField(
        tester,
        text: 'munich',
        bias: null,
        onDownloadArea: () {},
      );

      expect(find.text('Munich'), findsOneWidget);
      expect(find.text('Download this area to search offline'), findsNothing);
    });

    testWidgets('a search that failed still offers the download', (
      tester,
    ) async {
      await pumpField(
        tester,
        text: 'munich',
        bias: outsideTheTile,
        photonBody: 'not json at all',
        onDownloadArea: () {},
      );

      expect(find.text('Search failed.'), findsOneWidget);
      expect(
        find.text('Download this area to search offline'),
        findsOneWidget,
        reason: 'no network is when the download matters most',
      );
    });

    testWidgets('the online results offer the way back to the local ones', (
      tester,
    ) async {
      final h = await pumpField(tester, onDownloadArea: () {});
      expect(find.text('Show offline results'), findsNothing);

      await tester.tap(find.text('Search online for \u201cvaduz\u201d'));
      await tester.pumpAndSettle();

      expect(h.photonAdapter.requests, hasLength(1));
      expect(find.text('Munich'), findsOneWidget);
      final back = find.text('Show offline results');
      expect(back, findsOneWidget);
      expect(find.byIcon(Icons.offline_pin_outlined), findsOneWidget);
      expect(find.text('Download this area to search offline'), findsNothing);

      await tester.tap(back);
      await tester.pumpAndSettle();

      expect(find.text('Vaduz'), findsOneWidget);
      expect(find.text('Munich'), findsNothing);
      expect(find.text('Search online for \u201cvaduz\u201d'), findsOneWidget);
      expect(
        h.photonAdapter.requests,
        hasLength(1),
        reason: 'the way back costs no request',
      );
    });

    testWidgets('an empty gazetteer directory goes online as before', (
      tester,
    ) async {
      final h = await pumpField(tester, empty: true, text: 'munich');

      expect(h.photonAdapter.requests, hasLength(1));
      expect(find.text('Munich'), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsWidgets);
      expect(find.byIcon(Icons.travel_explore_outlined), findsNothing);
    });
  });
}

/// Every kind the gazetteer can answer with, as the rows show it.
///
/// The table is the contract: a kind added to the store without an icon and a
/// label here is a row that says nothing, which is the bug this guards.
const _kinds =
    <({SearchKind kind, String? detail, IconData icon, String label})>[
      (
        kind: SearchKind.place,
        detail: 'city',
        icon: Icons.location_city_outlined,
        label: 'City',
      ),
      (
        kind: SearchKind.place,
        detail: 'town',
        icon: Icons.domain_outlined,
        label: 'Town',
      ),
      (
        kind: SearchKind.place,
        detail: 'village',
        icon: Icons.cottage_outlined,
        label: 'Village',
      ),
      (
        kind: SearchKind.place,
        detail: 'hamlet',
        icon: Icons.house_outlined,
        label: 'Hamlet',
      ),
      (
        kind: SearchKind.place,
        detail: 'suburb',
        icon: Icons.maps_home_work_outlined,
        label: 'Suburb',
      ),
      (
        kind: SearchKind.place,
        detail: 'neighbourhood',
        icon: Icons.maps_home_work_outlined,
        label: 'Neighbourhood',
      ),
      (
        kind: SearchKind.place,
        detail: 'locality',
        icon: Icons.pin_drop_outlined,
        label: 'Locality',
      ),
      (
        kind: SearchKind.place,
        detail: 'island',
        icon: Icons.waves_outlined,
        label: 'Island',
      ),
      (
        kind: SearchKind.street,
        detail: null,
        icon: Icons.signpost_outlined,
        label: 'Street',
      ),
      (
        kind: SearchKind.poi,
        detail: 'drinking_water',
        icon: Icons.water_drop_outlined,
        label: 'Drinking water',
      ),
      (
        kind: SearchKind.poi,
        detail: 'toilets',
        icon: Icons.wc_outlined,
        label: 'Toilets',
      ),
      (
        kind: SearchKind.poi,
        detail: 'bicycle_rental',
        icon: Icons.directions_bike_outlined,
        label: 'Bike rental',
      ),
      (
        kind: SearchKind.poi,
        detail: 'charging_station',
        icon: Icons.ev_station_outlined,
        label: 'E-bike charging',
      ),
      (
        kind: SearchKind.poi,
        detail: 'pharmacy',
        icon: Icons.local_pharmacy_outlined,
        label: 'Pharmacy',
      ),
      (
        kind: SearchKind.poi,
        detail: 'picnic_site',
        icon: Icons.deck_outlined,
        label: 'Picnic site',
      ),
      (
        kind: SearchKind.poi,
        detail: 'bicycle_parking',
        icon: Icons.local_parking_outlined,
        label: 'Bike parking',
      ),
      (
        kind: SearchKind.poi,
        detail: 'cafe',
        icon: Icons.local_cafe_outlined,
        label: 'Cafe',
      ),
      (
        kind: SearchKind.poi,
        detail: 'bicycle_repair_station',
        icon: Icons.build_outlined,
        label: 'Bike repair station',
      ),
      (
        kind: SearchKind.poi,
        detail: 'shelter',
        icon: Icons.house_siding_outlined,
        label: 'Shelter',
      ),
      (
        kind: SearchKind.poi,
        detail: 'bicycle_shop',
        icon: Icons.pedal_bike_outlined,
        label: 'Bike shop',
      ),
      (
        kind: SearchKind.poi,
        detail: 'station',
        icon: Icons.train_outlined,
        label: 'Station',
      ),
      (
        kind: SearchKind.poi,
        detail: 'viewpoint',
        icon: Icons.landscape_outlined,
        label: 'Viewpoint',
      ),
      (
        kind: SearchKind.poi,
        detail: 'peak',
        icon: Icons.terrain_outlined,
        label: 'Peak',
      ),
      (
        kind: SearchKind.poi,
        detail: 'park',
        icon: Icons.park_outlined,
        label: 'Park',
      ),
      (
        kind: SearchKind.poi,
        detail: 'attraction',
        icon: Icons.attractions_outlined,
        label: 'Attraction',
      ),
      (
        kind: SearchKind.poi,
        detail: 'museum',
        icon: Icons.museum_outlined,
        label: 'Museum',
      ),
      (
        kind: SearchKind.poi,
        detail: 'historic',
        icon: Icons.account_balance_outlined,
        label: 'Historic site',
      ),
      (
        kind: SearchKind.poi,
        detail: 'place_of_worship',
        icon: Icons.church_outlined,
        label: 'Place of worship',
      ),
      (
        kind: SearchKind.poi,
        detail: 'hospital',
        icon: Icons.local_hospital_outlined,
        label: 'Hospital',
      ),
      (
        kind: SearchKind.poi,
        detail: 'university',
        icon: Icons.school_outlined,
        label: 'University',
      ),
      (
        kind: SearchKind.poi,
        detail: 'stadium',
        icon: Icons.stadium_outlined,
        label: 'Sports venue',
      ),
      (
        kind: SearchKind.poi,
        detail: 'mall',
        icon: Icons.local_mall_outlined,
        label: 'Shopping centre',
      ),
      (
        kind: SearchKind.poi,
        detail: 'airport',
        icon: Icons.flight_outlined,
        label: 'Airport',
      ),
      (
        kind: SearchKind.poi,
        detail: 'ferry_terminal',
        icon: Icons.directions_boat_outlined,
        label: 'Ferry terminal',
      ),
      (
        kind: SearchKind.poi,
        detail: 'tower',
        icon: Icons.cell_tower_outlined,
        label: 'Tower',
      ),
      (
        kind: SearchKind.poi,
        detail: 'lighthouse',
        icon: Icons.lightbulb_outline,
        label: 'Lighthouse',
      ),
      (
        kind: SearchKind.poi,
        detail: 'water',
        icon: Icons.water_outlined,
        label: 'Water',
      ),
      (
        kind: SearchKind.poi,
        detail: 'beach',
        icon: Icons.beach_access_outlined,
        label: 'Beach',
      ),
      (
        kind: SearchKind.poi,
        detail: 'nature_reserve',
        icon: Icons.forest_outlined,
        label: 'Nature reserve',
      ),
      (
        kind: SearchKind.poi,
        detail: 'building',
        icon: Icons.apartment_outlined,
        label: 'Building',
      ),
      (
        kind: SearchKind.poi,
        detail: 'mountain_pass',
        icon: Icons.hiking,
        label: 'Mountain pass',
      ),
      (
        kind: SearchKind.poi,
        detail: 'camp_site',
        icon: Icons.holiday_village_outlined,
        label: 'Campsite',
      ),
      (
        kind: SearchKind.poi,
        detail: 'hotel',
        icon: Icons.hotel_outlined,
        label: 'Hotel',
      ),
      (
        kind: SearchKind.poi,
        detail: 'hostel',
        icon: Icons.bed_outlined,
        label: 'Hostel',
      ),
      (
        kind: SearchKind.poi,
        detail: 'alpine_hut',
        icon: Icons.cabin_outlined,
        label: 'Mountain hut',
      ),
      (
        kind: SearchKind.poi,
        detail: 'supermarket',
        icon: Icons.shopping_cart_outlined,
        label: 'Supermarket',
      ),
      (
        kind: SearchKind.poi,
        detail: 'bakery',
        icon: Icons.bakery_dining_outlined,
        label: 'Bakery',
      ),
      // The fallbacks: a POI kind this build does not know, and no kind at all.
      (
        kind: SearchKind.poi,
        detail: 'graffiti_wall',
        icon: Icons.place_outlined,
        label: 'Place',
      ),
      (
        kind: SearchKind.poi,
        detail: null,
        icon: Icons.place_outlined,
        label: 'Place',
      ),
    ];

SearchResult _local(SearchKind kind, String? detail, {String? city}) =>
    SearchResult(
      name: 'Somewhere',
      position: const LatLng(47, 9.5),
      source: SearchSource.local,
      kind: kind,
      detail: detail,
      city: city,
    );

void _kindTable() {
  final AppLocalizations l10n = AppLocalizationsEn();

  for (final row in _kinds) {
    final name = '${row.kind.name}/${row.detail ?? 'none'}';
    test('$name shows ${row.label}', () {
      final result = _local(row.kind, row.detail);
      expect(searchResultIcon(result), row.icon);
      expect(searchKindLabel(l10n, result), row.label);
      expect(localResultSubtitle(l10n, result), row.label);
      expect(
        localResultSubtitle(l10n, _local(row.kind, row.detail, city: 'Vaduz')),
        '${row.label} · Vaduz',
      );
    });
  }

  test('an unclassified local row keeps the neutral pin and no label', () {
    final result = _local(SearchKind.unknown, null);
    expect(searchResultIcon(result), Icons.place_outlined);
    expect(searchKindLabel(l10n, result), isEmpty);
    expect(
      localResultSubtitle(
        l10n,
        _local(SearchKind.unknown, null, city: 'Vaduz'),
      ),
      'Vaduz',
    );
  });

  test('a row with no name at all is titled by what it is', () {
    SearchResult unnamed(String? detail, {SearchKind kind = SearchKind.poi}) =>
        SearchResult(
          name: '',
          position: const LatLng(47, 9.5),
          source: SearchSource.local,
          kind: kind,
          detail: detail,
        );

    expect(
      searchResultTitle(l10n, unnamed('drinking_water')),
      'Drinking water',
    );
    expect(searchResultTitle(l10n, unnamed('bicycle_parking')), 'Bike parking');
    expect(
      searchResultTitle(l10n, unnamed(null, kind: SearchKind.unknown)),
      'Place',
      reason: 'a row that is nothing in particular still needs a title',
    );
    expect(
      searchResultTitle(l10n, _local(SearchKind.poi, 'drinking_water')),
      'Somewhere',
      reason: 'a name is never replaced',
    );
  });

  test('a row found by its kind says how far away it is', () {
    SearchResult tap({required double meters, String? city}) => SearchResult(
      name: '',
      position: const LatLng(47, 9.5),
      source: SearchSource.local,
      kind: SearchKind.poi,
      detail: 'drinking_water',
      city: city,
      distanceMeters: meters,
    );

    expect(
      localResultSubtitle(l10n, tap(meters: 350), units: UnitSystem.metric),
      '350 m',
    );
    expect(
      localResultSubtitle(l10n, tap(meters: 2400), units: UnitSystem.metric),
      '2.4 km',
    );
    expect(
      localResultSubtitle(l10n, tap(meters: 120), units: UnitSystem.imperial),
      '390 ft',
    );
    expect(
      localResultSubtitle(l10n, tap(meters: 350), units: UnitSystem.imperial),
      '0.2 mi',
    );
    expect(
      localResultSubtitle(
        l10n,
        tap(meters: 350, city: 'Vaduz'),
        units: UnitSystem.metric,
      ),
      '350 m \u00b7 Vaduz',
    );
    expect(
      localResultSubtitle(l10n, tap(meters: 350)),
      '',
      reason:
          'a row the units are not known for keeps the distance to itself, '
          'and an unnamed row already wears its kind as its title',
    );
    expect(
      localResultSubtitle(
        l10n,
        _local(SearchKind.poi, 'cafe'),
        units: UnitSystem.metric,
      ),
      'Cafe',
      reason: 'a name match was not found by its distance',
    );
  });

  test('the keyword table maps every label the app can print', () {
    final table = localisedKindKeywords(l10n);

    expect(table['drinking water'], 'drinking_water');
    expect(table['toilets'], 'toilets');
    expect(table['bike rental'], 'bicycle_rental');
    expect(table['e-bike charging'], 'charging_station');
    expect(table['pharmacy'], 'pharmacy');
    expect(table['picnic site'], 'picnic_site');
    expect(table['bike parking'], 'bicycle_parking');
    expect(
      table.containsKey('place'),
      isFalse,
      reason: 'the fallback label names no kind',
    );
  });

  test('a house number sits between the kind and the place', () {
    SearchResult street({required String number, bool approximate = false}) =>
        SearchResult(
          name: 'West 42nd Street',
          position: const LatLng(40.76, -74),
          source: SearchSource.local,
          kind: SearchKind.street,
          city: 'Manhattan',
          houseNumber: number,
          approximate: approximate,
        );

    expect(
      localResultSubtitle(l10n, street(number: '400')),
      'Street \u00b7 400 \u00b7 Manhattan',
    );
    expect(
      localResultSubtitle(l10n, street(number: '410', approximate: true)),
      'Street \u00b7 \u2248 410 \u00b7 Manhattan',
      reason: 'an interpolated position says so',
    );
    expect(
      localResultSubtitle(
        l10n,
        SearchResult(
          name: 'Feldweg',
          position: const LatLng(47, 9.5),
          source: SearchSource.local,
          kind: SearchKind.street,
          houseNumber: '7',
        ),
      ),
      'Street \u00b7 7',
      reason: 'the separator is only put where there is something to separate',
    );
  });

  test('an online row keeps the neutral pin whatever its kind', () {
    for (final row in _kinds) {
      expect(
        searchResultIcon(
          SearchResult(
            name: 'Somewhere',
            position: const LatLng(47, 9.5),
            kind: row.kind,
            detail: row.detail,
          ),
        ),
        Icons.place_outlined,
        reason: '${row.kind.name}/${row.detail}',
      );
    }
  });
}
