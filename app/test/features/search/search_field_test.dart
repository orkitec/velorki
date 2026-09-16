import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki/l10n/generated/app_localizations_en.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/pump.dart';
import 'support/gazetteer_fixture.dart';

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
    List<Override> storeOverride({bool empty = false}) {
      if (!empty) {
        buildGazetteer(
          dir,
          'E5_N45',
          places: fixturePlaces,
          streets: fixtureStreets,
          pois: fixturePois,
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
    }) async {
      final h = await pumpScreen(
        tester,
        Scaffold(body: SearchField(onSelected: (_) {})),
        harness: PlannerHarness(withGeocoder: withGeocoder),
        extraOverrides: storeOverride(empty: empty),
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
      expect(find.byIcon(Icons.location_city_outlined), findsWidgets);
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
        icon: Icons.location_city_outlined,
        label: 'Town',
      ),
      (
        kind: SearchKind.place,
        detail: 'village',
        icon: Icons.location_city_outlined,
        label: 'Village',
      ),
      (
        kind: SearchKind.place,
        detail: 'hamlet',
        icon: Icons.location_city_outlined,
        label: 'Hamlet',
      ),
      (
        kind: SearchKind.place,
        detail: 'suburb',
        icon: Icons.location_city_outlined,
        label: 'Suburb',
      ),
      (
        kind: SearchKind.place,
        detail: 'neighbourhood',
        icon: Icons.location_city_outlined,
        label: 'Neighbourhood',
      ),
      (
        kind: SearchKind.place,
        detail: 'locality',
        icon: Icons.location_city_outlined,
        label: 'Locality',
      ),
      (
        kind: SearchKind.place,
        detail: 'island',
        icon: Icons.location_city_outlined,
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
