import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/settings/presentation/appearance_section.dart';

import '../../support/app.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
  String cyclosmTileUrl = '',
  bool expectTextFits = true,
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      effectiveConfigProvider.overrideWithValue(
        AppConfig(cyclosmTileUrl: cyclosmTileUrl),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Scrolling, as on the Settings page.
      child: testApp(
        home: const Scaffold(
          body: SingleChildScrollView(child: AppearanceSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The test font draws every glyph a full em wide, so a narrow screen cuts
  // text the app's own font fits (see CLAUDE.md).
  if (expectTextFits) expectNoClippedText(tester);
  return container;
}

/// The tappable swatch carrying [label].
Finder _swatch(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell));

void main() {
  testWidgets('the section offers the three modes and the five accents', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    for (final label in [
      l10n.appearanceModeSystem,
      l10n.appearanceModeLight,
      l10n.appearanceModeDark,
    ]) {
      // "Light" is also a map look chip, so look inside the segments.
      expect(
        find.descendant(
          of: find.byType(SegmentedButton<ThemeMode>),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    for (final label in [
      l10n.mapLookAuto,
      l10n.mapLookNight,
      l10n.mapLookBlack,
    ]) {
      expect(
        find.descendant(
          of: find.byType(SegmentedButton<MapLook>),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    for (final label in [
      l10n.accentVolt,
      l10n.accentEmber,
      l10n.accentGlacier,
      l10n.accentBerry,
      l10n.accentForest,
    ]) {
      expect(_swatch(label), findsOneWidget);
      // A screen reader hears the accent's name on the swatch.
      expect(tester.getSemantics(_swatch(label)).label, contains(label));
    }

    final segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(segmented.selected, {ThemeMode.system});
    semantics.dispose();
  });

  testWidgets('on a narrow phone every segment stays on one line', (
    tester,
  ) async {
    tester.view.physicalSize =
        const Size(360, 740) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    await _pump(
      tester,
      cyclosmTileUrl: 'https://tiles.example/{z}/{x}/{y}.png',
      expectTextFits: false,
    );
    for (final look in MapLook.values) {
      final label = tester.widget<Text>(
        find.descendant(
          of: find.byType(SegmentedButton<MapLook>),
          matching: find.text(mapLookLabel(l10n, look)),
        ),
      );
      expect(label.maxLines, 1);
    }
    // One row: every segment at the same height.
    final tops = {
      for (final look in MapLook.values)
        tester
            .getRect(
              find.descendant(
                of: find.byType(SegmentedButton<MapLook>),
                matching: find.text(mapLookLabel(l10n, look)),
              ),
            )
            .center
            .dy,
    };
    expect(tops, hasLength(1));
    for (final style in BarStyle.values) {
      final label = find.descendant(
        of: find.byType(SegmentedButton<BarStyle>),
        matching: find.text(barStyleLabel(l10n, style)),
      );
      expect(tester.widget<Text>(label).maxLines, 1);
      expect(tester.widget<Text>(label).softWrap, isFalse);
    }
    final barTops = {
      for (final style in BarStyle.values)
        tester
            .getRect(
              find.descendant(
                of: find.byType(SegmentedButton<BarStyle>),
                matching: find.text(barStyleLabel(l10n, style)),
              ),
            )
            .center
            .dy,
    };
    expect(barTops, hasLength(1));
    // Each label within its own segment: shrunk to fit, never spilling.
    for (final style in BarStyle.values) {
      final label = find.descendant(
        of: find.byType(SegmentedButton<BarStyle>),
        matching: find.text(barStyleLabel(l10n, style)),
      );
      final segment = tester.getRect(
        find.ancestor(of: label, matching: find.byType(FittedBox)).first,
      );
      final drawn = tester.getRect(label);
      expect(drawn.left, greaterThanOrEqualTo(segment.left - 0.5));
      expect(drawn.right, lessThanOrEqualTo(segment.right + 0.5));
    }
    // The choice's title on one line, its hint wrapping inside the section.
    final section = tester.getRect(find.byType(AppearanceSection));
    final title = tester.renderObject<RenderParagraph>(
      find.text(l10n.appearanceGlass),
    );
    expect(title.size.width, lessThanOrEqualTo(section.width - 40));
    expect(
      title.size.height,
      lessThan(title.text.style!.fontSize! * 2),
      reason: '"${l10n.appearanceGlass}" on one line',
    );
    final hint = find.text(l10n.appearanceGlassHint);
    final hintRect = tester.getRect(hint);
    expect(hintRect.left, greaterThanOrEqualTo(section.left + 20 - 0.5));
    expect(hintRect.right, lessThanOrEqualTo(section.right - 20 + 0.5));
    expect(
      tester.renderObject<RenderParagraph>(hint).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('tapping Dark switches the mode and stores it', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text(l10n.appearanceModeDark));
    await tester.pumpAndSettle();

    expect(container.read(appearanceSettingProvider).mode, ThemeMode.dark);
    final segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(segmented.selected, {ThemeMode.dark});
  });

  testWidgets('tapping the Ember swatch switches the accent', (tester) async {
    final container = await _pump(tester);
    expect(container.read(appearanceSettingProvider).accent, AccentPreset.volt);

    await tester.ensureVisible(_swatch(l10n.accentEmber));
    await tester.tap(_swatch(l10n.accentEmber));
    await tester.pumpAndSettle();

    expect(
      container.read(appearanceSettingProvider).accent,
      AccentPreset.ember,
    );
  });

  testWidgets('the stored choice is the one shown when the section opens', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: <String, Object>{
        'appearance.mode': 'light',
        'appearance.accent': 'berry',
      },
    );

    final segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(segmented.selected, {ThemeMode.light});
    // The selected swatch is the one wearing the check mark.
    expect(
      find.descendant(
        of: _swatch(l10n.accentBerry),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('tapping Night switches the map look', (tester) async {
    final container = await _pump(tester);
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.auto);

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<MapLook>),
        matching: find.text(l10n.mapLookNight),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(appearanceSettingProvider).mapLook, MapLook.night);
  });

  testWidgets('the online map choice shows in every build', (tester) async {
    await _pump(tester);

    expect(find.byType(SegmentedButton<OverlayDarkMode>), findsOneWidget);
    expect(find.text(l10n.appearanceOverlayDarkTitle), findsOneWidget);
  });

  testWidgets('choosing Dimmed switches the overlay and stores it', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      cyclosmTileUrl: 'https://{s}.tile.cyclosm.org/{z}/{x}/{y}.png',
    );
    expect(find.text(l10n.appearanceOverlayDarkTitle), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<OverlayDarkMode>>(
            find.byType(SegmentedButton<OverlayDarkMode>),
          )
          .selected,
      {OverlayDarkMode.inverted},
    );

    await tester.tap(find.text(l10n.appearanceOverlayDarkDimmed));
    await tester.pumpAndSettle();

    expect(
      container.read(appearanceSettingProvider).overlayDark,
      OverlayDarkMode.dimmed,
    );
    expect(
      tester
          .widget<SegmentedButton<OverlayDarkMode>>(
            find.byType(SegmentedButton<OverlayDarkMode>),
          )
          .selected,
      {OverlayDarkMode.dimmed},
    );
  });

  testWidgets('the stored overlay choice is the one shown', (tester) async {
    await _pump(
      tester,
      initial: <String, Object>{'appearance.overlay_dark': 'unchanged'},
      cyclosmTileUrl: 'https://{s}.tile.cyclosm.org/{z}/{x}/{y}.png',
    );

    expect(
      tester
          .widget<SegmentedButton<OverlayDarkMode>>(
            find.byType(SegmentedButton<OverlayDarkMode>),
          )
          .selected,
      {OverlayDarkMode.unchanged},
    );
  });

  testWidgets('choosing Subtle glass switches the glass and stores it', (
    tester,
  ) async {
    final container = await _pump(tester);
    SegmentedButton<BarStyle> segmented() =>
        tester.widget<SegmentedButton<BarStyle>>(
          find.byType(SegmentedButton<BarStyle>),
        );
    expect(find.text(l10n.appearanceGlass), findsOneWidget);
    expect(find.text(l10n.appearanceGlassHint), findsOneWidget);
    expect(segmented().selected, {BarStyle.clear});

    await tester.ensureVisible(find.text(l10n.appearanceBarSubtle));
    await tester.tap(find.text(l10n.appearanceBarSubtle));
    await tester.pumpAndSettle();

    expect(container.read(appearanceSettingProvider).barStyle, BarStyle.subtle);
    expect(segmented().selected, {BarStyle.subtle});
  });

  testWidgets('the stored bar style is the one shown', (tester) async {
    await _pump(tester, initial: <String, Object>{'appearance.bar': 'solid'});

    expect(
      tester
          .widget<SegmentedButton<BarStyle>>(
            find.byType(SegmentedButton<BarStyle>),
          )
          .selected,
      {BarStyle.solid},
    );
  });

  testWidgets('the rain radar is soft until As measured is chosen, which is '
      'stored', (tester) async {
    final container = await _pump(tester);
    SegmentedButton<RadarStyle> segmented() =>
        tester.widget<SegmentedButton<RadarStyle>>(
          find.byType(SegmentedButton<RadarStyle>),
        );
    expect(find.text(l10n.appearanceRadarStyle), findsOneWidget);
    expect(find.text(l10n.appearanceRadarHint), findsOneWidget);
    expect(segmented().selected, {RadarStyle.soft});
    expect(
      container.read(appearanceSettingProvider).radarStyle,
      RadarStyle.soft,
    );

    await tester.ensureVisible(find.text(l10n.appearanceRadarMeasured));
    await tester.tap(find.text(l10n.appearanceRadarMeasured));
    await tester.pumpAndSettle();

    expect(
      container.read(appearanceSettingProvider).radarStyle,
      RadarStyle.measured,
    );
    expect(segmented().selected, {RadarStyle.measured});
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getString('map.weather.radar_style'), 'measured');

    // Back to Soft, the default, which is stored as no choice at all.
    await tester.tap(find.text(l10n.appearanceRadarSoft));
    await tester.pumpAndSettle();
    expect(
      container.read(appearanceSettingProvider).radarStyle,
      RadarStyle.soft,
    );
    expect(prefs.getString('map.weather.radar_style'), isNull);
  });

  testWidgets('the stored radar look is the one shown', (tester) async {
    await _pump(
      tester,
      initial: <String, Object>{'map.weather.radar_style': 'measured'},
    );

    expect(
      tester
          .widget<SegmentedButton<RadarStyle>>(
            find.byType(SegmentedButton<RadarStyle>),
          )
          .selected,
      {RadarStyle.measured},
    );
  });
}
