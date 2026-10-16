import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/presentation/location_rationale_dialog.dart';

import '../../support/app.dart';

/// Opens the dialog from a button and keeps what it answered.
Future<List<bool>> _open(WidgetTester tester) async {
  final answers = <bool>[];
  await tester.pumpWidget(
    testApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                answers.add(await showLocationRationaleDialog(context)),
            child: const Icon(Icons.my_location),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(TextButton));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  testWidgets('says why before the system asks, and continues on allow', (
    tester,
  ) async {
    final answers = await _open(tester);

    expect(find.text(l10n.mapLocationRationaleTitle), findsOneWidget);
    expect(find.text(l10n.mapLocationRationaleBody), findsOneWidget);
    await tester.tap(find.text(l10n.mapLocationRationaleAllow));
    await tester.pumpAndSettle();

    expect(answers, <bool>[true]);
    expect(find.text(l10n.mapLocationRationaleTitle), findsNothing);
  });

  testWidgets('declining does not go on to the system prompt', (tester) async {
    final answers = await _open(tester);

    await tester.tap(find.text(l10n.mapLocationRationaleDeny));
    await tester.pumpAndSettle();

    expect(answers, <bool>[false]);
  });

  testWidgets('closing it some other way counts as declining', (tester) async {
    final answers = await _open(tester);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(answers, <bool>[false]);
  });
}
