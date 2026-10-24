import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/store_prompts/presentation/store_update_dialog.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import '../../support/app.dart';

/// A screen with a button that opens the dialog and keeps the answer.
class _Opener extends StatefulWidget {
  const _Opener({required this.downloaded});

  final bool downloaded;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  bool? answer;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          final chosen = await showStoreUpdateDialog(
            context,
            downloaded: widget.downloaded,
          );
          setState(() => answer = chosen);
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  // The suite runs in the language under test; the dialog is also checked in
  // English and German here, whichever that is.
  for (final locale in <Locale>{
    testLocale,
    const Locale('en'),
    const Locale('de'),
  }) {
    final strings = lookupAppLocalizations(locale);

    testWidgets('the update dialog in "$locale": Update and Later', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(home: const _Opener(downloaded: false), locale: locale),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(strings.storeUpdateTitle), findsOneWidget);
      expect(find.text(strings.storeUpdateBody), findsOneWidget);
      expectNoClippedText(tester);

      await tester.tap(find.text(strings.storeUpdateAction));
      await tester.pumpAndSettle();
      expect(find.byType(StoreUpdateDialog), findsNothing);
      expect(tester.state<_OpenerState>(find.byType(_Opener)).answer, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.storeUpdateLater));
      await tester.pumpAndSettle();
      expect(tester.state<_OpenerState>(find.byType(_Opener)).answer, isFalse);
    });

    testWidgets('the restart dialog in "$locale"', (tester) async {
      await tester.pumpWidget(
        testApp(home: const _Opener(downloaded: true), locale: locale),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(strings.storeUpdateReadyTitle), findsOneWidget);
      expect(find.text(strings.storeUpdateReadyBody), findsOneWidget);
      expectNoClippedText(tester);
      await tester.tap(find.text(strings.storeUpdateRestart));
      await tester.pumpAndSettle();
      expect(tester.state<_OpenerState>(find.byType(_Opener)).answer, isTrue);
    });
  }
}
