import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';

import '../../support/app.dart';
import '../../support/contrast.dart';
import '../recording/support/pump.dart';

/// What the [panel]'s glass is drawn with.
({bool blurred, ImageFilter? filter, Color fill}) _panel(
  WidgetTester tester,
  Finder panel,
) {
  final backdrop = tester.widget<BackdropFilter>(
    find.descendant(of: panel, matching: find.byType(BackdropFilter)),
  );
  final material = tester.widget<Material>(
    find.descendant(of: panel, matching: find.byType(Material)).first,
  );
  return (
    blurred: backdrop.enabled,
    filter: backdrop.filter,
    fill: material.color!,
  );
}

/// Holds the glass panel [panel] to what [style] promises the chrome over
/// the map: the bar's glass a quarter less see-through, blurred as the bar.
void _expectPanel(
  WidgetTester tester,
  Finder panel,
  BarStyle style,
  VelorkiColors colors,
) {
  final glass = _panel(tester, panel);
  expect(glass.fill, colors.chromeFill(style));
  final filter = floatingBarFilter(style);
  expect(glass.blurred, filter != null);
  if (filter != null) expect(glass.filter, filter);
}

/// The fill an unselected bike chip at [tester] is painted with.
Color _chipFill(WidgetTester tester, RouteProfile profile) {
  final ink = tester.widget<Ink>(
    find
        .ancestor(
          of: find.text(profileLabel(l10n, profile)),
          matching: find.byType(Ink),
        )
        .first,
  );
  return (ink.decoration! as ShapeDecoration).color!;
}

Future<void> _pump(
  WidgetTester tester, {
  BarStyle? style,
  bool highContrast = false,
  ThemeData? theme,
}) async {
  final content = Column(
    children: [
      const GlassPanel(
        padding: EdgeInsets.all(12),
        child: Text('over the map'),
      ),
      ProfileChipRow(
        glass: true,
        selected: RouteProfile.gravel,
        onSelected: (_) {},
      ),
    ],
  );
  await tester.pumpWidget(
    testApp(
      theme: theme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: highContrast),
          child: Scaffold(
            body: style == null
                ? content
                : FloatingBarStyle(style: style, child: content),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final (name, theme) in [
    ('light', buildLightTheme()),
    ('dark', buildDarkTheme()),
  ]) {
    for (final style in BarStyle.values) {
      testWidgets('$name, ${style.name}: the panel and the chips', (
        tester,
      ) async {
        await _pump(tester, style: style, theme: theme);
        _expectPanel(tester, find.byType(GlassPanel), style, theme.velorki);
        // The chips take the chrome's glass, never blurred: no shadow to
        // hide the square corners of a blur over the map's native view; in
        // clear glass the subtle glass's thicker fill, so a map label behind
        // one does not compete with its text.
        expect(
          _chipFill(tester, RouteProfile.trekking),
          theme.velorki.chromeFill(
            style == BarStyle.clear ? BarStyle.subtle : style,
          ),
        );
        expect(
          find.descendant(
            of: find.byType(ProfileChipRow),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
        // Nothing opaque under a chip's glass: its Material takes the
        // canvas colour.
        expect(
          Theme.of(tester.element(find.byType(ChoiceChip).first)).canvasColor,
          Colors.transparent,
        );
        // Readable over the darkest and the lightest map.
        for (final map in [Colors.black, Colors.white]) {
          for (final profile in RouteProfile.values) {
            expectReadable(
              tester,
              find.text(profileLabel(l10n, profile)),
              over: map,
              reason: '$name ${style.name} chip ${profile.name} over $map',
            );
          }
          final label = find.text('over the map');
          final fill = Color.alphaBlend(theme.velorki.chromeFill(style), map);
          expect(
            contrastRatio(textColorOf(tester, label), fill),
            greaterThanOrEqualTo(4.5),
            reason: '$name ${style.name} panel over $map',
          );
        }
      });
    }
  }

  testWidgets('without a scope the chrome is clear glass', (tester) async {
    await _pump(tester);
    final colors = buildLightTheme().velorki;
    _expectPanel(tester, find.byType(GlassPanel), BarStyle.clear, colors);
    // The chips' clear glass is the subtle glass's fill (no blur there).
    expect(
      _chipFill(tester, RouteProfile.trekking),
      colors.chromeFill(BarStyle.subtle),
    );
  });

  testWidgets('a system asking for more contrast gets solid chrome', (
    tester,
  ) async {
    await _pump(tester, style: BarStyle.clear, highContrast: true);
    final colors = buildLightTheme().velorki;
    _expectPanel(tester, find.byType(GlassPanel), BarStyle.solid, colors);
    expect(_chipFill(tester, RouteProfile.trekking), colors.barSolid);
  });

  testWidgets('on the Plan tab the search field and the chips follow the '
      'stored style, the bar keeps its own glass', (tester) async {
    const size = Size(402, 874);
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = size * 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: size,
      preferences: const <String, Object>{'appearance.bar': 'subtle'},
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    final colors = buildLightTheme().velorki;
    _expectPanel(
      tester,
      find
          .descendant(
            of: find.byType(SearchField),
            matching: find.byType(GlassPanel),
          )
          .first,
      BarStyle.subtle,
      colors,
    );
    // Trekking is the profile that is on; another is the chip's glass.
    expect(
      _chipFill(tester, RouteProfile.mtb),
      colors.chromeFill(BarStyle.subtle),
    );
    // The bar itself is the bar's glass, a quarter more see-through.
    final bar = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(FloatingBarShell),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (bar.decoration! as BoxDecoration).color,
      colors.barFill(BarStyle.subtle),
    );
    await unmountApp(tester);
  });
}
