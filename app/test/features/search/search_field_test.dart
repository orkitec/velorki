import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/search_field.dart';

import '../planner/support/pump.dart';

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
}
