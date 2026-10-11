import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/shared/application/nav_bar_docking.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';

import '../../support/app.dart';
import '../recording/support/pump.dart';

/// What the glass of the one floating bar on screen is drawn with.
({
  bool blurred,
  bool grouped,
  ImageFilter? filter,
  Color fill,
  Color? rim,
  List<BoxShadow> shadows,
})
_glass(WidgetTester tester) {
  final shell = find.byType(FloatingBarShell);
  expect(shell, findsOneWidget);
  final shadowBox = tester.widget<DecoratedBox>(
    find.descendant(of: shell, matching: find.byType(DecoratedBox)).first,
  );
  final blur = find.descendant(
    of: shell,
    matching: find.byType(BackdropFilter),
  );
  final backdrop = tester.widget<BackdropFilter>(blur);
  final glass = tester.widget<Container>(
    find.descendant(of: shell, matching: find.byType(Container)).first,
  );
  final decoration = glass.decoration;
  final fill = decoration is BarGlassDecoration
      ? decoration.fill!
      : (decoration! as BoxDecoration).color!;
  final foreground = glass.foregroundDecoration;
  return (
    blurred: backdrop.enabled,
    grouped: isGroupedBlur(tester, blur),
    filter: backdrop.filter,
    fill: fill,
    rim: foreground is BarGlassDecoration ? foreground.rim : null,
    shadows: (shadowBox.decoration as BoxDecoration).boxShadow ?? const [],
  );
}

/// Holds the glass at [tester] to what [style] promises, [docked] or not.
void _expectStyle(
  WidgetTester tester,
  BarStyle style, {
  required bool docked,
  required VelorkiColors colors,
}) {
  final glass = _glass(tester);
  expect(glass.fill, glassTint(colors, style));
  // Out of the app's backdrop group: at rest the bar lies over the tab's
  // card, which is painted after the group reads the map.
  expect(glass.grouped, isFalse);
  final filter = floatingBarFilter(style);
  // Docked the bar blurs nothing of its own: the sheet lays one blur behind
  // its strip and the bar together, and the bar paints only its tint.
  expect(glass.blurred, !docked && filter != null);
  if (filter != null) expect(glass.filter, filter);
  expect(glass.rim, isNull, reason: 'no style draws a rim');
  if (docked) {
    // Beside the seam a shadow would show as dark wedges under the strip.
    expect(glass.shadows, isEmpty);
  } else {
    // Outside the bar only and not shifted: under thin glass a shadow
    // inside the shape would show through and darken it.
    final shadow = glass.shadows.single;
    expect(shadow.blurStyle, BlurStyle.outer);
    expect(shadow.offset, Offset.zero);
  }
}

const _destinations = [
  NavigationDestination(icon: Icon(Icons.route), label: 'Plan'),
  NavigationDestination(icon: Icon(Icons.circle), label: 'Record'),
];

Future<void> _pumpBar(
  WidgetTester tester, {
  required BarStyle style,
  required bool docked,
  RailSide? rail,
  bool highContrast = false,
  ThemeData? theme,
}) async {
  final size = rail == null ? const Size(390, 844) : const Size(844, 390);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final bar = FloatingNavigationBar(
    selectedIndex: 0,
    onDestinationSelected: (_) {},
    docked: docked,
    railSide: rail,
    destinations: _destinations,
  );
  await tester.pumpWidget(
    testApp(
      theme: theme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: highContrast),
          child: FloatingBarStyle(
            style: style,
            child: Scaffold(
              body: rail == null
                  ? Align(alignment: Alignment.bottomCenter, child: bar)
                  : Stack(children: [Positioned.fill(child: bar)]),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('the glass of each style', () {
    final light = buildLightTheme().velorki;
    final dark = buildDarkTheme().velorki;

    test('solid is opaque, subtle faintly see-through, clear clearly', () {
      for (final colors in [light, dark]) {
        expect(colors.barSolid.a, 1);
        expect(colors.barTransparent.a, inInclusiveRange(0.76, 0.82));
        expect(colors.barTransparent.withValues(alpha: 1), colors.barSolid);
        expect(colors.barSubtle.a, inInclusiveRange(0.5, 0.7));
        expect(colors.barClear.a, inInclusiveRange(0.3, 0.56));
        // The same glass at each step, only more or less of it.
        expect(colors.barSubtle.withValues(alpha: 1), colors.barSolid);
        expect(colors.barClear.withValues(alpha: 1), colors.barSolid);
      }
      // Light labels on dark glass need a little more of it over a light map.
      expect(dark.barSubtle.a, greaterThan(light.barSubtle.a));
      expect(dark.barClear.a, greaterThan(light.barClear.a));
    });

    test('solid and transparent blur nothing, subtle blurs more than clear, '
        'each a plain blur iOS applies over the map', () {
      expect(floatingBarFilter(BarStyle.solid), isNull);
      expect(floatingBarFilter(BarStyle.transparent), isNull);
      expect(
        floatingBarFilter(BarStyle.subtle),
        ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      );
      expect(
        floatingBarFilter(BarStyle.clear),
        ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      );
      for (final style in [BarStyle.subtle, BarStyle.clear]) {
        final filter = floatingBarFilter(style).toString();
        expect(filter, isNot(contains('compose')));
        expect(filter, isNot(contains('matrix')));
      }
    });

    // The bar and the controls take this one tint on every platform; on
    // iOS the system's blur frosts the map first, so the thinnest there.
    for (final (platform, clear, subtle) in [
      (TargetPlatform.iOS, 0.18, 0.30),
      (TargetPlatform.android, 0.24, 0.36),
      (TargetPlatform.macOS, 0.24, 0.36),
    ]) {
      test('on ${platform.name} the glass styles are a thin tint of the bar '
          'glass, $clear clear and $subtle subtle', () {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        for (final colors in [light, dark]) {
          for (final style in BarStyle.values) {
            // The same glass, only less of it.
            expect(
              glassTint(colors, style).withValues(alpha: 1),
              colors.barSolid,
            );
          }
          expect(glassTint(colors, BarStyle.clear).a, closeTo(clear, 1e-3));
          expect(glassTint(colors, BarStyle.subtle).a, closeTo(subtle, 1e-3));
          // Without a blur the tint is the theme's.
          expect(glassTint(colors, BarStyle.solid), colors.barSolid);
          expect(
            glassTint(colors, BarStyle.transparent),
            colors.barTransparent,
          );
        }
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  testWidgets('on iOS the bar at rest is the thin tint over its blur', (
    tester,
  ) async {
    for (final style in [BarStyle.clear, BarStyle.subtle]) {
      await _pumpBar(tester, style: style, docked: false);
      final colors = buildLightTheme().velorki;
      _expectStyle(tester, style, docked: false, colors: colors);
      expect(
        _glass(tester).fill.a,
        closeTo(style == BarStyle.clear ? 0.18 : 0.30, 1e-3),
      );
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final style in BarStyle.values) {
    for (final docked in [false, true]) {
      final where = docked ? 'docked' : 'at rest';
      testWidgets('upright, ${style.name} $where', (tester) async {
        await _pumpBar(tester, style: style, docked: docked);
        _expectStyle(
          tester,
          style,
          docked: docked,
          colors: buildLightTheme().velorki,
        );
      });

      testWidgets('sideways, ${style.name} $where', (tester) async {
        await _pumpBar(
          tester,
          style: style,
          docked: docked,
          rail: RailSide.left,
        );
        expect(find.byType(NavigationRail), findsOneWidget);
        _expectStyle(
          tester,
          style,
          docked: docked,
          colors: buildLightTheme().velorki,
        );
      });
    }
  }

  testWidgets('in the dark theme the dark glass of the style', (tester) async {
    await _pumpBar(
      tester,
      style: BarStyle.clear,
      docked: false,
      theme: buildDarkTheme(),
    );
    _expectStyle(
      tester,
      BarStyle.clear,
      docked: false,
      colors: buildDarkTheme().velorki,
    );
  });

  testWidgets('a system asking for more contrast gets the solid bar', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      style: BarStyle.clear,
      docked: false,
      highContrast: true,
    );
    _expectStyle(
      tester,
      BarStyle.solid,
      docked: false,
      colors: buildLightTheme().velorki,
    );
  });

  testWidgets('without a scope the bar is clear glass', (tester) async {
    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: _destinations,
            ),
          ),
        ),
      ),
    );
    _expectStyle(
      tester,
      BarStyle.clear,
      docked: false,
      colors: buildLightTheme().velorki,
    );
  });

  group('the shell', () {
    setUp(() => debugShellLayoutOverride = null);
    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(SharedMapHost)));

    testWidgets('draws the bar and the docked sheet in the stored style, '
        'upright', (tester) async {
      const size = Size(402, 874);
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = size * 3;
      await pumpRecordingApp(
        tester,
        initialLocation: plannerRoute,
        surfaceSize: size,
        preferences: const <String, Object>{'appearance.bar': 'clear'},
        expectTextFits: false,
      );
      await tester.pumpAndSettle();
      final colors = buildLightTheme().velorki;
      _expectStyle(tester, BarStyle.clear, docked: false, colors: colors);

      await tester.dragFrom(
        tester.getCenter(find.byType(SheetHandle)),
        const Offset(0, 900),
      );
      await tester.pumpAndSettle();
      expect(container(tester).read(navBarDockingProvider), {plannerRoute});
      _expectStyle(tester, BarStyle.clear, docked: true, colors: colors);
      // The strip docked on it is the same glass.
      final strip = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(DockingSheetShell),
              matching: find.byType(DecoratedBox),
            )
            .at(1),
      );
      expect(
        (strip.decoration as BoxDecoration).color,
        glassTint(colors, BarStyle.clear),
      );
      await unmountApp(tester);
    });

    testWidgets('draws the rail in the stored style, sideways', (tester) async {
      const channel = MethodChannel(ScreenSideChannel.channelName);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'side' ? RailSide.left.name : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const size = Size(874, 402);
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = size * 3;
      await pumpRecordingApp(
        tester,
        initialLocation: plannerRoute,
        surfaceSize: size,
        preferences: const <String, Object>{'appearance.bar': 'solid'},
        expectTextFits: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      final colors = buildLightTheme().velorki;
      _expectStyle(tester, BarStyle.solid, docked: false, colors: colors);

      await tester.dragFrom(
        tester.getRect(find.byType(DockingSheetShell)).center,
        const Offset(-874, 0),
      );
      await tester.pumpAndSettle();
      expect(container(tester).read(navBarDockingProvider), {plannerRoute});
      _expectStyle(tester, BarStyle.solid, docked: true, colors: colors);
      await unmountApp(tester);
    });
  });
}
