import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/features/settings/data/package_info_provider.dart';
import 'package:velorki/features/settings/presentation/about_section.dart';

import '../../support/app.dart';

void main() {
  // The map's own credit is text only; the one that leads anywhere is here.
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
}
