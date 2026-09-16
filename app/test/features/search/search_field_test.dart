import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/search_field.dart';

import '../planner/support/pump.dart';
import 'support/gazetteer_fixture.dart';

void main() {
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
