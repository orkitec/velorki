import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/features/guide/data/guide_repository.dart';
import 'package:velorki/features/guide/domain/guide.dart';
import 'package:velorki/features/guide/presentation/guide_screen.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';

import '../../support/app.dart';
import '../../support/settings.dart';
import '../planner/support/pump.dart';

/// The page's own scroll, not a table's.
final _vertical = find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

void main() {
  late List<GuidePage> pages;
  final opened = <Uri>[];

  /// The app on the Settings tab, its guide the bundled one as
  /// `tool/gen.sh` copied it, in the test's language.
  Future<void> pumpSettings(WidgetTester tester) async {
    pages = (await tester.runAsync(
      () => loadGuide(rootBundle, testLocale.languageCode),
    ))!;
    opened.clear();
    await pumpApp(
      tester,
      initialLocation: settingsRoute,
      extraOverrides: [
        guideProvider(testLocale.languageCode)
            .overrideWith((ref) async => pages),
        linkOpenerProvider.overrideWithValue((url) async {
          opened.add(url);
          return true;
        }),
      ],
    );
    await tester.pumpAndSettle();
    await openSettingsTopic(tester, SettingsTopic.guide);
  }

  Future<void> openPage(WidgetTester tester, GuidePage page) async {
    final row = find.byKey(ValueKey<String>(page.slug));
    await tester.scrollUntilVisible(row, 200, scrollable: _vertical);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets('Settings → Guide lists the pages in order', (tester) async {
    await pumpSettings(tester);
    expect(pages.first.slug, 'getting-started');
    expect(pages.length, greaterThan(10));

    expect(find.widgetWithText(AppBar, l10n.settingsGuide), findsOneWidget);
    final rows = tester
        .widgetList<ListTile>(
          find.descendant(
            of: find.byType(GuideContents),
            matching: find.byType(ListTile),
          ),
        )
        .map((tile) => (tile.key! as ValueKey<String>).value)
        .toList();
    expect(rows, pages.map((p) => p.slug).take(rows.length).toList());
    expect(find.text(pages.first.title), findsOneWidget);
    expect(find.text(pages.first.description), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a page shows its title and its table', (tester) async {
    await pumpSettings(tester);
    final page = pages.firstWhere((p) => p.slug == 'import-and-export');
    await openPage(tester, page);

    expect(find.widgetWithText(AppBar, page.title), findsOneWidget);
    final table = find.byType(Table);
    await tester.scrollUntilVisible(table.first, 300, scrollable: _vertical);
    expect(table, findsWidgets);
    // A table wider than the screen scrolls on its own, sideways.
    expect(
      find.ancestor(
        of: table.first,
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });

  testWidgets('a link to another page opens it in the app', (tester) async {
    await pumpSettings(tester);
    final loops = pages.firstWhere((p) => p.slug == 'loops');
    final assistant = pages.firstWhere((p) => p.slug == 'assistant');
    await openPage(tester, loops);

    // The link's words, as the page writes `[words](./assistant)`.
    final words = RegExp(r'\[([^\]]+)\]\(\./assistant\)')
        .firstMatch(loops.body)!
        .group(1)!;
    final link = find.textContaining(words, findRichText: true).first;
    await tester.scrollUntilVisible(link, 300, scrollable: _vertical);
    await tester.tapOnText(find.textRange.ofSubstring(words).first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, assistant.title), findsOneWidget);
    expect(opened, isEmpty);
    await unmountApp(tester);
  });
}
