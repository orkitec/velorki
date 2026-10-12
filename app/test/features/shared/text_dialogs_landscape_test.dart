import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/library/presentation/edit_text_dialog.dart';
import 'package:velorki/features/library/presentation/rename_route_dialog.dart';
import 'package:velorki/features/planner/presentation/save_route_dialog.dart';
import 'package:velorki/features/recording/presentation/rename_ride_dialog.dart';

import '../../support/app.dart';

/// A phone turned sideways with the keyboard up leaves a dialog about a
/// quarter of the screen: each dialog that asks for text still lays out
/// there, its buttons in reach.
void main() {
  final dialogs = <String, Future<String?> Function(BuildContext)>{
    'save route': (c) => showSaveRouteDialog(c, initialName: 'Route 11 Oct'),
    'rename route': (c) => showRenameRouteDialog(c, initialName: 'Coast'),
    'rename ride': (c) => showRenameRideDialog(c, initialName: 'Evening'),
    'edit text': (c) => showEditTextDialog(c, title: 'Notes', initial: 'x'),
  };

  for (final MapEntry(key: name, value: open) in dialogs.entries) {
    testWidgets('$name fits sideways with the keyboard up', (tester) async {
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      // The keyboard covers 70 % of the height.
      tester.view.viewInsets = const FakeViewPadding(bottom: 1080 * 0.7);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        testApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      // The buttons are laid out inside the dialog, so a tap reaches them.
      final dialog = tester.getRect(find.byType(Dialog));
      for (final button in tester.widgetList<Widget>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byWidgetPredicate(
            (w) => w is TextButton || w is FilledButton,
          ),
        ),
      )) {
        final rect = tester.getRect(find.byWidget(button));
        expect(rect.bottom, lessThanOrEqualTo(dialog.bottom + 0.5));
      }
    });
  }

  testWidgets('upright, with room to spare, it is the usual alert dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showSaveRouteDialog(context, initialName: 'A'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
