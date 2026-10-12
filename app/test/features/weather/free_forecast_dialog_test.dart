import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/weather/presentation/free_forecast_dialog.dart';

import '../../support/app.dart';

/// The free forecast's dialog on the smallest phone turned sideways: it
/// lays out, its text scrolls, and every button is inside it and answers.
void main() {
  for (final size in const [Size(667, 375), Size(402, 874)]) {
    testWidgets('fits at ${size.width.round()} × ${size.height.round()}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FreeForecastAnswer? answer;
      await tester.pumpWidget(
        testApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => answer = await showFreeForecastDialog(
                  context,
                  offerPlus: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final dialog = tester.getRect(find.byType(Dialog));
      final buttons = find.descendant(
        of: find.byType(Dialog),
        matching: find.byWidgetPredicate(
          (w) => w is TextButton || w is FilledButton,
        ),
      );
      expect(buttons, findsNWidgets(3));
      for (final button in tester.widgetList<Widget>(buttons)) {
        final rect = tester.getRect(find.byWidget(button));
        expect(rect.bottom, lessThanOrEqualTo(dialog.bottom + 0.5));
        expect(rect.top, greaterThanOrEqualTo(dialog.top - 0.5));
      }
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(answer, FreeForecastAnswer.use);
    });
  }
}
