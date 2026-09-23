import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/planner/presentation/waypoint_edit_sheet.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/smart_loop/presentation/smart_loop_sheet.dart';

import '../features/planner/support/pump.dart';
import '../support/app.dart';
import '../support/contrast.dart';

/// Every chip, tile and header button label the tabs show, under each
/// theme: the label's colour against the fill it is painted on has to reach
/// WCAG's 4.5:1, so a tint that reads in one theme cannot slip through in
/// the other. White text on the accent's light tint did.
void main() {
  final themes = <String, ThemeData>{
    for (final preset in AccentPreset.values) ...{
      'dark ${preset.name}': buildDarkTheme(preset),
      'light ${preset.name}': buildLightTheme(preset),
    },
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    group(name, () {
      testWidgets('the Loop sheet\'s bike chips', (tester) async {
        final h = PlannerHarness();
        addTearDown(h.db.close);
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: h.overrides(prefs),
            child: testApp(
              theme: theme,
              home: const Scaffold(body: SmartLoopSheet()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final profile in RouteProfile.values) {
          expectReadable(
            tester,
            find.text(profileLabel(l10n, profile)),
            reason: '$name loop chip ${profile.name}',
          );
        }
      });

      testWidgets('the Plan chrome\'s bike chips and the theme\'s chips', (
        tester,
      ) async {
        await tester.pumpWidget(
          testApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  ProfileChipRow(
                    glass: true,
                    selected: RouteProfile.gravel,
                    onSelected: (_) {},
                  ),
                  ProfileChipRow(
                    selected: RouteProfile.mtb,
                    onSelected: (_) {},
                  ),
                  ChoiceChip(
                    label: const Text('chosen'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  ChoiceChip(
                    label: const Text('offered'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final profile in RouteProfile.values) {
          final labels = find.text(profileLabel(l10n, profile));
          expect(labels, findsNWidgets(2));
          expectReadable(tester, labels.first, reason: '$name glass chip');
          expectReadable(tester, labels.last, reason: '$name sheet chip');
        }
        expectReadable(tester, find.text('chosen'), reason: '$name chip');
        expectReadable(tester, find.text('offered'), reason: '$name chip');
      });

      testWidgets('the waypoint sheet\'s type tiles', (tester) async {
        await tester.pumpWidget(
          testApp(
            theme: theme,
            home: Scaffold(
              body: PoiKindTiles(selected: PoiKind.food, onSelected: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final kind in PoiKind.values) {
          expectReadable(
            tester,
            find.text(poiKindLabel(l10n, kind)),
            reason: '$name tile ${kind.name}',
          );
        }
      });

      testWidgets('the Record and Library header actions', (tester) async {
        await tester.pumpWidget(
          testApp(
            theme: theme,
            home: Scaffold(
              body: Row(
                children: [
                  LabeledIconButton(
                    icon: Icons.save_outlined,
                    label: 'Filled',
                    filled: true,
                    onPressed: () {},
                  ),
                  LabeledIconButton(
                    icon: Icons.share_outlined,
                    label: 'Plain',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // The caption sits on the sheet, the icon on the circle: the
        // caption against the scaffold's surface, as the sheet paints it.
        final surface = theme.colorScheme.surface;
        for (final label in ['Filled', 'Plain']) {
          final text = textColorOf(tester, find.text(label));
          expect(
            contrastRatio(text, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$name header caption $label',
          );
        }
        final filled = tester.widget<Icon>(find.byIcon(Icons.save_outlined));
        expect(
          contrastRatio(filled.color!, theme.colorScheme.primary),
          greaterThanOrEqualTo(4.5),
          reason: '$name filled header icon',
        );
        final plain = tester.widget<Icon>(find.byIcon(Icons.share_outlined));
        expect(
          contrastRatio(plain.color!, theme.colorScheme.surfaceContainerHigh),
          greaterThanOrEqualTo(4.5),
          reason: '$name plain header icon',
        );
      });
    });
  }
}
