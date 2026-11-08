import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/settings/data/package_info_provider.dart';
import 'package:velorki/features/settings/presentation/about_section.dart';

import '../../support/app.dart';

void main() {
  // The credit in Settings → About leads to OpenStreetMap's copyright page.
  testWidgets('the OpenStreetMap credit opens the copyright page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final opened = <Uri>[];
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
          linkOpenerProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
        ],
        child: testApp(
          home: const Scaffold(
            body: SingleChildScrollView(child: AboutSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, l10n.osmAttribution);
    expect(
      find.descendant(of: tile, matching: find.byIcon(Icons.open_in_new)),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://www.openstreetmap.org/copyright')]);
  });

  testWidgets('the imprint opens the site\'s imprint in the app\'s language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final opened = <Uri>[];
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
          linkOpenerProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
        ],
        child: testApp(
          home: const Scaffold(
            body: SingleChildScrollView(child: AboutSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, l10n.settingsImprint);
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final String lang = testLocale.languageCode;
    expect(opened, [
      Uri.parse(
        lang == 'en'
            ? 'https://velorki.com/imprint'
            : 'https://velorki.com/$lang/imprint',
      ),
    ]);
  });

  /// Pumps the section with [plusOffered] as the flavour says it.
  Future<void> pumpAbout(
    WidgetTester tester, {
    required bool plusOffered,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
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
          plusOfferedProvider.overrideWithValue(plusOffered),
        ],
        child: testApp(
          home: const Scaffold(
            body: SingleChildScrollView(child: AboutSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a build that offers no Plus says here what it leaves out', (
    tester,
  ) async {
    // The F-Droid flavour, and nothing else: a rider who downloaded that
    // build can read what is missing without hunting for it.
    await pumpAbout(tester, plusOffered: false);

    expect(find.text(l10n.settingsFlavourTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.settingsFlavourBody), findsOneWidget);
    // It names F-Droid, no other store, and leads nowhere.
    expect(l10n.settingsFlavourBody, contains('F-Droid'));
    for (final elsewhere in ['Google Play', 'App Store', 'http']) {
      expect(l10n.settingsFlavourBody, isNot(contains(elsewhere)));
    }
    expect(
      find.widgetWithText(ListTile, l10n.settingsFlavourTitle),
      findsNothing,
    );
  });

  testWidgets('and every other build says nothing of the kind', (tester) async {
    await pumpAbout(tester, plusOffered: true);

    expect(find.text(l10n.settingsFlavourTitle.toUpperCase()), findsNothing);
    expect(find.text(l10n.settingsFlavourBody), findsNothing);
    // The rest of About is there either way.
    expect(find.text(l10n.settingsLicenses), findsOneWidget);
  });
}
