import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/presentation/ai_settings_section.dart';
import 'package:velorki/features/assistant/presentation/assistant_strings.dart';

import '../../support/app.dart';

Future<(ProviderContainer, List<Uri>)> _pump(
  WidgetTester tester, {
  AiConsent? consent,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (consent != null) aiConsentPrefsKey: consent.name,
  });
  final prefs = await SharedPreferences.getInstance();
  final opened = <Uri>[];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      linkOpenerProvider.overrideWithValue((url) async {
        opened.add(url);
        return true;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: const Scaffold(body: AiSettingsSection())),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return (container, opened);
}

void main() {
  testWidgets('a rider who was never asked is told so', (tester) async {
    await _pump(tester);
    expect(find.text(l10n.settingsAiConsentNotAsked), findsOneWidget);
  });

  testWidgets('the stored consent is named exactly', (tester) async {
    await _pump(tester, consent: AiConsent.withLocation);
    expect(find.text(l10n.settingsAiConsentWithLocation), findsOneWidget);
  });

  testWidgets('the consent can be revoked from settings', (tester) async {
    final (container, _) = await _pump(tester, consent: AiConsent.withLocation);

    await tester.tap(find.text(l10n.settingsAiChange));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.recordingBatteryLater));
    await tester.pumpAndSettle();

    expect(container.read(aiConsentControllerProvider), AiConsent.denied);
    expect(find.text(l10n.settingsAiConsentDenied), findsOneWidget);
  });

  testWidgets('reporting an answer opens a mail to support', (tester) async {
    final (_, opened) = await _pump(tester, consent: AiConsent.textOnly);

    await tester.tap(find.text(l10n.settingsAiReport));
    await tester.pumpAndSettle();

    expect(opened.single.toString(), aiReportMailto);
    expect(opened.single.scheme, 'mailto');
  });
}
