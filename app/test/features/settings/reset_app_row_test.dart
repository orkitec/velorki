import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/settings/application/app_reset.dart';
import 'package:velorki/features/settings/data/package_info_provider.dart';
import 'package:velorki/features/settings/presentation/about_section.dart';

import '../../support/app.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester, {required bool dev}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final calls = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          packageInfoProvider.overrideWith(
            (ref) async => PackageInfo(
              appName: 'Velorki',
              packageName: 'com.velorki',
              version: '1.0.0',
              buildNumber: '1',
            ),
          ),
          devToolsAvailableProvider.overrideWithValue(dev),
          appResetProvider.overrideWithValue(
            AppReset(
              clearPreferences: () async => calls.add('prefs'),
              deleteOfflineMaps: () async => calls.add('maps'),
              closeDatabase: () async => calls.add('close'),
              clearSecureStorage: () async => calls.add('secure'),
              directories: () async => [],
              endApp: () => calls.add('end'),
            ),
          ),
        ],
        child: testApp(
          home: const Scaffold(
            body: SingleChildScrollView(child: AboutSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('a release build has no reset row', (tester) async {
    await pump(tester, dev: false);
    expect(find.text(l10n.settingsResetApp), findsNothing);
  });

  testWidgets('cancelling the dialog resets nothing', (tester) async {
    final calls = await pump(tester, dev: true);
    final row = find.text(l10n.settingsResetApp);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsResetAppBody), findsOneWidget);

    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsResetAppBody), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('confirming runs the reset', (tester) async {
    final calls = await pump(tester, dev: true);
    final row = find.text(l10n.settingsResetApp);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.settingsResetAppConfirm));
    await tester.pumpAndSettle();
    expect(calls, ['maps', 'close', 'prefs', 'secure', 'end']);
  });
}
