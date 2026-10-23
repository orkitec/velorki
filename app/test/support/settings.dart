import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';

/// The overview's row for [topic].
Finder settingsRow(SettingsTopic topic) =>
    find.byKey(ValueKey<SettingsTopic>(topic));

/// On the Settings tab's overview, scrolls to [topic]'s row and opens its
/// page.
Future<void> openSettingsTopic(WidgetTester tester, SettingsTopic topic) async {
  final row = settingsRow(topic);
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
}
