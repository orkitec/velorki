import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/performance/data/show_performance_setting.dart';
import 'package:velorki/features/performance/presentation/performance_hud.dart';
import 'package:velorki/features/settings/data/package_info_provider.dart';
import 'package:velorki/features/settings/presentation/about_section.dart';
import 'package:velorki/features/shared/presentation/gesture_zone_guard.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import '../../support/app.dart';

Future<ProviderContainer> _container({
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
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
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The app's builder chain, as `VelorkiApp` has it, over a screen with a
/// button in the corner the box covers.
Future<void> _pumpApp(
  WidgetTester tester,
  ProviderContainer container, {
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        locale: testLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PerformanceHudLayer(child: gestureZoneAppBuilder(context, child)),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 300,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Lets the box refresh its figures.
Future<void> _refresh(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  test('the setting is off until turned on, and is kept', () async {
    final container = await _container();
    expect(container.read(showPerformanceProvider), isFalse);
    await container.read(showPerformanceProvider.notifier).set(true);
    expect(container.read(showPerformanceProvider), isTrue);

    final prefs = container.read(sharedPreferencesProvider);
    final again = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(again.dispose);
    expect(again.read(showPerformanceProvider), isTrue);
  });

  testWidgets('Settings → About has the switch, off, and it turns the box on', (
    tester,
  ) async {
    tester.view.physicalSize =
        const Size(360, 740) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final container = await _container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(
          home: const Scaffold(
            body: SingleChildScrollView(child: AboutSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectNoClippedText(tester);

    final tile = find.widgetWithText(
      SwitchListTile,
      l10n.settingsShowPerformance,
    );
    expect(find.text(l10n.settingsShowPerformanceHint), findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(container.read(showPerformanceProvider), isTrue);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool('debug.showPerformance'),
      isTrue,
    );
  });

  testWidgets('no box while the setting is off', (tester) async {
    final container = await _container();
    await _pumpApp(tester, container);
    expect(find.byKey(performanceHudKey), findsNothing);
    expect(find.byType(PerformanceHud), findsNothing);
  });

  testWidgets('the box shows when on, fits at 360 dp and takes no touch', (
    tester,
  ) async {
    tester.view.physicalSize =
        const Size(360, 740) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final container = await _container(
      initial: <String, Object>{'debug.showPerformance': true},
    );
    var taps = 0;
    await _pumpApp(tester, container, onTap: () => taps++);
    await _refresh(tester);

    final box = find.byKey(performanceHudKey);
    expect(box, findsOneWidget);
    final shown = tester
        .widgetList<RichText>(
          find.descendant(of: box, matching: find.byType(RichText)),
        )
        .map((t) => t.text.toPlainText())
        .join('\n');
    for (final label in [
      l10n.perfFps,
      l10n.perfUi,
      l10n.perfRaster,
      l10n.perfJank,
      l10n.perfMemory,
    ]) {
      expect(shown, contains(label));
    }
    expect(
      find.ancestor(of: box, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
    // Two short lines under the status bar, inside the screen even in the
    // test font, which draws every glyph a full em wide (the real box is
    // about 60 % as wide).
    final rect = tester.getRect(box);
    expect(rect.height, lessThan(30));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));

    // The button under the box still gets the tap.
    await tester.tapAt(tester.getCenter(box));
    await tester.pump();
    expect(taps, 1);

    // Off again: the box and its timings go.
    await container.read(showPerformanceProvider.notifier).set(false);
    await tester.pump();
    expect(box, findsNothing);
  });

  testWidgets('sideways the box keeps clear of the camera on the left', (
    tester,
  ) async {
    tester.view.physicalSize =
        const Size(800, 360) * tester.view.devicePixelRatio;
    tester.view.viewPadding = FakeViewPadding(
      left: 59 * tester.view.devicePixelRatio,
      bottom: 21 * tester.view.devicePixelRatio,
    );
    tester.view.padding = tester.view.viewPadding;
    addTearDown(tester.view.reset);
    final container = await _container(
      initial: <String, Object>{'debug.showPerformance': true},
    );
    await _pumpApp(tester, container);
    await _refresh(tester);
    final rect = tester.getRect(find.byKey(performanceHudKey));
    expect(rect.left, greaterThanOrEqualTo(59));
    expect(rect.top, 0);
    expect(rect.right, lessThanOrEqualTo(800));
    await container.read(showPerformanceProvider.notifier).set(false);
    await tester.pump();
  });

  testWidgets('the box stays above a modal sheet', (tester) async {
    final container = await _container(
      initial: <String, Object>{'debug.showPerformance': true},
    );
    await _pumpApp(tester, container);
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => const SizedBox.expand(),
      ),
    );
    await tester.pumpAndSettle();
    await _refresh(tester);
    // The sheet is on the navigator, inside the app; the box is the app's
    // sibling, painted after it.
    expect(find.byKey(performanceHudKey), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(performanceHudKey),
        matching: find.byType(Navigator),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byType(BottomSheet),
        matching: find.byType(PerformanceHudLayer),
      ),
      findsOneWidget,
    );
    await container.read(showPerformanceProvider.notifier).set(false);
    await tester.pump();
  });
}
