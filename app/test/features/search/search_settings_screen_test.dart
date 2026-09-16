import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/search/data/search_preferences_controller.dart';
import 'package:velorki/features/search/domain/search_group.dart';
import 'package:velorki/features/search/presentation/search_settings_screen.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

Future<ProviderContainer> pumpPage(
  WidgetTester tester, {
  Map<String, Object> stored = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SearchSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The group names as the page lists them, top to bottom.
List<String> shownOrder(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((tile) => ((tile.title! as Text).data)!)
    .toList();

void main() {
  testWidgets('all eight groups are listed, on, in the default order', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('Search'), findsOneWidget);
    expect(
      find.text(
        'What offline search shows, and in which order. Drag to change the '
        'priority.',
      ),
      findsOneWidget,
    );
    expect(shownOrder(tester), <String>[
      'Places',
      'Streets and addresses',
      'Landmarks',
      'Cycling stops',
      'Overnight',
      'Nature',
      'Transport',
      'Services',
    ]);
    expect(find.byType(Switch), findsNWidgets(8));
    expect(
      tester.widgetList<Switch>(find.byType(Switch)).every((s) => s.value),
      isTrue,
    );
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(8));
  });

  testWidgets('dragging a row by its handle reorders it and persists', (
    tester,
  ) async {
    final container = await pumpPage(tester);
    final handles = find.byIcon(Icons.drag_handle);
    final rowHeight = tester.getSize(find.byType(ListTile).first).height;

    // Cycling stops, the fourth row, up to the top.
    final gesture = await tester.startGesture(tester.getCenter(handles.at(3)));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    for (var step = 0; step < 4; step++) {
      await gesture.moveBy(Offset(0, -rowHeight));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(shownOrder(tester).first, 'Cycling stops');
    expect(
      container.read(searchPreferencesProvider).order.first,
      SearchGroup.cyclingStops,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('search.groupOrder')?.first,
      SearchGroup.cyclingStops.name,
    );
  });

  testWidgets('a switch turns a group off and persists', (tester) async {
    final container = await pumpPage(tester);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Switch>(find.byType(Switch).at(1)).value,
      isFalse,
      reason: 'the row shows the new state without a reload',
    );
    expect(container.read(searchPreferencesProvider).disabled, <SearchGroup>{
      SearchGroup.streets,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('search.groupsDisabled'), <String>['streets']);
  });

  testWidgets('a stored order and a stored switch are what the page shows', (
    tester,
  ) async {
    await pumpPage(
      tester,
      stored: const <String, Object>{
        'search.groupOrder': <String>['nature', 'places'],
        'search.groupsDisabled': <String>['nature'],
      },
    );

    expect(shownOrder(tester).take(2), <String>['Nature', 'Places']);
    expect(tester.widgetList<Switch>(find.byType(Switch)).first.value, isFalse);
  });
}
