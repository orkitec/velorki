import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/shared/presentation/placeholder_body.dart';

import '../../support/app.dart';

void main() {
  testWidgets('shows its icon and its line, centred, at an ordinary height', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        home: const Scaffold(
          body: PlaceholderBody(icon: Icons.inbox_outlined, message: 'Empty'),
        ),
      ),
    );
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Centred: the text is below the icon, both around the middle.
    final icon = tester.getCenter(find.byIcon(Icons.inbox_outlined));
    final text = tester.getCenter(find.text('Empty'));
    expect(text.dy, greaterThan(icon.dy));
    expect(icon.dx, closeTo(text.dx, 1));
  });

  testWidgets('never overflows, however little height it is given', (
    tester,
  ) async {
    // A docked card leaves the body a sliver of height; the fonts on a
    // Linux CI box are a shade taller than a Mac's, which is where the
    // column used to overflow by twenty pixels.
    for (final height in [40.0, 8.0, 0.0]) {
      await tester.pumpWidget(
        testApp(
          home: Scaffold(
            body: SizedBox(
              height: height,
              child: const PlaceholderBody(
                icon: Icons.inbox_outlined,
                message:
                    'A line that is long enough to wrap onto a second '
                    'line at a narrow width, as a real message does',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'height $height');
    }
  });
}
