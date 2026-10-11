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
({bool blurred, bool grouped, ImageFilter? filter, Color fill}) _panel(
  WidgetTester tester,
  Finder panel,
) {
  final blur = find.descendant(
    of: panel,
    matching: find.byType(BackdropFilter),
  );
  final backdrop = tester.widget<BackdropFilter>(blur);
  final material = tester.widget<Material>(
    find.descendant(of: panel, matching: find.byType(Material)).first,
  );
  return (
    blurred: backdrop.enabled,
    grouped: isGroupedBlur(tester, blur),
    filter: backdrop.filter,
    fill: material.color!,
  );
}

/// Holds the glass panel [panel] to what [style] promises the chrome over
/// the map: the bar's own tint, blurred as the bar, in the app's one
/// backdrop group.
void _expectPanel(
  WidgetTester tester,
  Finder panel,
  BarStyle style,
  VelorkiColors colors,
) {
  final glass = _panel(tester, panel);
  expect(glass.fill, glassTint(colors, style));
  final filter = floatingBarFilter(style);
  expect(glass.blurred, filter != null);
  if (filter != null) expect(glass.filter, filter);
  expect(glass.grouped, isTrue, reason: 'one backdrop read for the chrome');
}

/// Holds every bike chip to the glass [style] promises: each its own blur
/// over the map, in a stadium clip that is the chip's own outline.
void _expectChipGlass(WidgetTester tester, BarStyle style) {
  final filter = floatingBarFilter(style);
  final chips = find.byType(ChoiceChip);
  expect(chips, findsNWidgets(RouteProfile.values.length));
  for (final chip in chips.evaluate()) {
    final chipFinder = find.byWidget(chip.widget);
    // The chip's box is what it draws, so the glass meets its outline; the
    // row keeps the height to tap.
    expect(
      (chip.widget as ChoiceChip).materialTapTargetSize,
      MaterialTapTargetSize.shrinkWrap,
    );
    final blur = find.ancestor(
      of: chipFinder,
      matching: find.byType(BackdropFilter),
    );
    expect(blur, findsOneWidget);
    final backdrop = tester.widget<BackdropFilter>(blur);
    expect(backdrop.enabled, filter != null, reason: '$style');
    if (filter != null) expect(backdrop.filter, filter);
    expect(isGroupedBlur(tester, blur), isTrue, reason: '$style');
    final clip = find.ancestor(of: blur, matching: find.byType(ClipRRect));
    expect(clip, findsOneWidget);
    // A stadium as four equal corners, the shape iOS clips a blur over the
    // map's native view to.
    final clipper = tester.widget<ClipRRect>(clip).clipper!;
    final size = tester.getSize(clip);
    expect(size, tester.getSize(chipFinder));
    expect(
      clipper.getClip(size),
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
    );
  }
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
        // The panel's shadow lies outside it only and is not shifted: under
        // thin glass a shadow inside the shape would show through.
        final shadow =
            (tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: find.byType(GlassPanel),
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .boxShadow!
                .single;
        expect(shadow.blurStyle, BlurStyle.outer);
        expect(shadow.offset, Offset.zero);
        // The chips are the same glass as the panel: its tint, its blur.
        expect(
          _chipFill(tester, RouteProfile.trekking),
          glassTint(theme.velorki, style),
        );
        _expectChipGlass(tester, style);
        // Nothing opaque under a chip's glass: its Material takes the
        // canvas colour.
        expect(
          Theme.of(tester.element(find.byType(ChoiceChip).first)).canvasColor,
          Colors.transparent,
        );
        // Readable over the theme's map as the blur leaves it, not over a
        // pure black or white: the blur averages the map behind the glass,
        // which is what the thin tint is laid on (see [blurredMapBehind]).
        final map = blurredMapBehind(theme.brightness);
        for (final profile in RouteProfile.values) {
          expectReadable(
            tester,
            find.text(profileLabel(l10n, profile)),
            over: map,
            reason: '$name ${style.name} chip ${profile.name}',
          );
        }
        final label = find.text('over the map');
        final fill = Color.alphaBlend(glassTint(theme.velorki, style), map);
        expect(
          contrastRatio(textColorOf(tester, label), fill),
          greaterThanOrEqualTo(4.5),
          reason: '$name ${style.name} panel over the blurred map',
        );
      });
    }
  }

  testWidgets('without a scope the chrome is clear glass', (tester) async {
    await _pump(tester);
    final colors = buildLightTheme().velorki;
    _expectPanel(tester, find.byType(GlassPanel), BarStyle.clear, colors);
    expect(
      _chipFill(tester, RouteProfile.trekking),
      glassTint(colors, BarStyle.clear),
    );
    _expectChipGlass(tester, BarStyle.clear);
  });

  testWidgets(
    'on iOS the panel and the chips take the bar tint, thin over the blur',
    (tester) async {
      for (final theme in [buildLightTheme(), buildDarkTheme()]) {
        for (final style in BarStyle.values) {
          await _pump(tester, style: style, theme: theme);
          // The app animates from one theme to the next.
          await tester.pumpAndSettle();
          final colors = theme.velorki;
          _expectPanel(tester, find.byType(GlassPanel), style, colors);
          // One material: the controls and the bar side by side over the
          // map are the same tint.
          final tint = glassTint(colors, style);
          expect(_panel(tester, find.byType(GlassPanel)).fill, tint);
          expect(_chipFill(tester, RouteProfile.trekking), tint);
          _expectChipGlass(tester, style);
          if (style == BarStyle.clear) expect(tint.a, closeTo(0.18, 1e-3));
          if (style == BarStyle.subtle) expect(tint.a, closeTo(0.30, 1e-3));
          // Readable over the theme's blurred map with the thinner tint
          // too; the system's frost on top of the blur only adds to it.
          final map = blurredMapBehind(theme.brightness);
          for (final profile in RouteProfile.values) {
            expectReadable(
              tester,
              find.text(profileLabel(l10n, profile)),
              over: map,
              reason: '${theme.brightness.name} ${style.name} chip on iOS',
            );
          }
          expect(
            contrastRatio(
              textColorOf(tester, find.text('over the map')),
              Color.alphaBlend(tint, map),
            ),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.brightness.name} ${style.name} panel on iOS',
          );
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a system asking for more contrast gets solid chrome', (
    tester,
  ) async {
    await _pump(tester, style: BarStyle.clear, highContrast: true);
    final colors = buildLightTheme().velorki;
    _expectPanel(tester, find.byType(GlassPanel), BarStyle.solid, colors);
    expect(_chipFill(tester, RouteProfile.trekking), colors.barSolid);
  });

  testWidgets('on the Plan tab the search field and the chips follow the '
      'stored style, the bar the same tint in a blur of its own', (
    tester,
  ) async {
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
      glassTint(colors, BarStyle.subtle),
    );
    // The bar is the same tint, but blurs on its own: at rest it lies over
    // the tab's card, painted after the group reads the map.
    final shell = find.byType(FloatingBarShell);
    final bar = tester.widget<Container>(
      find.descendant(of: shell, matching: find.byType(Container)).first,
    );
    expect(
      (bar.decoration! as BoxDecoration).color,
      glassTint(colors, BarStyle.subtle),
    );
    expect(
      isGroupedBlur(
        tester,
        find.descendant(of: shell, matching: find.byType(BackdropFilter)),
      ),
      isFalse,
    );
    await unmountApp(tester);
  });
}
