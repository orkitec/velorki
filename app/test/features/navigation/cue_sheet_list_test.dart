import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/navigation/application/route_cues.dart';
import 'package:velorki/features/navigation/presentation/cue_sheet_list.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';

LatLng _at(double alongM) => LatLng(48 + alongM / 111194.9266, 11);

void main() {
  testWidgets('a long cue sheet folds to eight lines and opens on request', (
    tester,
  ) async {
    final cues = routeCuesFor(
      <LatLng>[for (var i = 0; i <= 30; i++) _at(i * 100.0)],
      turns: <TurnHint>[
        for (var i = 1; i < 30; i += 2)
          TurnHint(
            pointIndex: i,
            kind: i % 4 == 1 ? TurnKind.left : TurnKind.right,
          ),
      ],
    );
    expect(cues, hasLength(16), reason: '15 turns and the finish');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final selected = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: testApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CueSheetList(
                cues: cues,
                selected: null,
                onSelect: selected.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.navTurnLeft), findsNWidgets(4));
    expect(find.text(l10n.cueSheetShowAll(16)), findsOneWidget);
    await tester.tap(find.text(l10n.cueSheetShowAll(16)));
    await tester.pump();
    expect(find.text(l10n.cueSheetShowFewer), findsOneWidget);
    expect(find.text(l10n.navTurnLeft), findsNWidgets(8));

    await tester.tap(find.text(l10n.navArrive));
    expect(selected, <int>[15]);
  });
}
