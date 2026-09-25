import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/live_figure_preferences.dart';
import 'package:velorki/features/recording/domain/live_figures.dart';
import 'package:velorki/features/recording/presentation/live_figures_settings_screen.dart';

import '../../support/app.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: const LiveFiguresSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return container;
}

/// The row of the figure captioned [label].
Finder _row(String label) => find.widgetWithText(ListTile, label);

void main() {
  testWidgets('every figure, in today\'s order, today\'s on and elapsed off, '
      'and nothing to reset', (tester) async {
    await _pump(tester);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, [
      l10n.statDistance,
      l10n.statSpeed,
      l10n.statAvgSpeed,
      l10n.statAscent,
      l10n.statDescent,
      l10n.statMovingTime,
      l10n.statHeartRate,
      l10n.statCadence,
      l10n.statPower,
      l10n.statRemaining,
      l10n.statArrival,
      l10n.statElapsed,
    ]);
    Switch switchOf(String label) => tester.widget<Switch>(
      find.descendant(of: _row(label), matching: find.byType(Switch)),
    );
    expect(switchOf(l10n.statDistance).value, isTrue);
    expect(switchOf(l10n.statElapsed).value, isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.restart_alt),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a figure dragged by its handle moves, a switch turns one off, '
      'and reset puts it all back', (tester) async {
    final container = await _pump(tester);
    final rowHeight = tester.getSize(_row(l10n.statDistance)).height;

    // Moving time, the sixth, up to the top.
    final handle = find.descendant(
      of: _row(l10n.statMovingTime),
      matching: find.byIcon(Icons.drag_handle),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(Offset(0, -rowHeight * 5.5 / 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: _row(l10n.statSpeed), matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();

    final p = container.read(liveFigurePreferencesProvider);
    expect(p.shown.first, LiveFigure.movingTime);
    expect(p.shown, isNot(contains(LiveFigure.speed)));

    await tester.tap(find.byTooltip(l10n.liveFiguresReset));
    await tester.pumpAndSettle();
    expect(container.read(liveFigurePreferencesProvider).isDefault, isTrue);
  });

  testWidgets('the last figure on cannot be switched off', (tester) async {
    await _pump(
      tester,
      initial: {
        'recording.figuresDisabled': [
          for (final f in LiveFigure.values)
            if (f != LiveFigure.distance) f.name,
        ],
      },
    );
    final last = tester.widget<Switch>(
      find.descendant(
        of: _row(l10n.statDistance),
        matching: find.byType(Switch),
      ),
    );
    expect(last.value, isTrue);
    expect(last.onChanged, isNull);
  });
}
