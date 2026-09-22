import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/tab_fade.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/tab_chrome_slide.dart';

import '../support/app.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  // The settings tab is long — subscription, connections, AI, advanced,
  // about — so the shell is pumped on a tall surface rather than scrolled to
  // every assertion.
  await tester.binding.setSurfaceSize(const Size(1000, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // The library tab reads the database; give it one that needs no platform.
  final db = VelorkiDatabase.memory();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        velorkiDatabaseProvider.overrideWithValue(db),
      ],
      child: testRouterApp(routerConfig: createRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Velorki',
      packageName: 'com.orkitec.velorki',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('shows four navigation destinations and starts on Plan', (
    tester,
  ) async {
    await _pumpShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    // The bar floats in its glass pill over a body that runs behind it.
    expect(find.byType(FloatingNavigationBar), findsOneWidget);
    expect(
      tester
          .widget<Scaffold>(
            find.ancestor(
              of: find.byType(FloatingNavigationBar),
              matching: find.byType(Scaffold),
            ),
          )
          .extendBody,
      isTrue,
    );
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in [
      l10n.tabPlan,
      l10n.tabRecord,
      l10n.tabLibrary,
      l10n.tabSettings,
    ]) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
  });

  testWidgets('the bar steps aside while the keyboard is up', (tester) async {
    await _pumpShell(tester);
    expect(find.byType(FloatingNavigationBar), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNavigationBar), findsNothing);
  });

  testWidgets('a docked sheet squares the bar, on that tab only', (
    tester,
  ) async {
    // The sheets size themselves from MediaQuery, so the view has to agree
    // with the surface for the geometry below to be exact.
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpShell(tester);
    FloatingNavigationBar bar() => tester.widget<FloatingNavigationBar>(
      find.byType(FloatingNavigationBar),
    );
    BoxDecoration barDecoration() =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(FloatingNavigationBar),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    List<BoxShadow>? barShadow() => barDecoration().boxShadow;
    BorderRadiusGeometry? barRadius() =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(FloatingNavigationBar),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .borderRadius;
    expect(bar().docked, isFalse);
    expect(barRadius(), BorderRadius.circular(30));
    expect(barShadow(), hasLength(1));

    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 1500),
    );
    await tester.pumpAndSettle();
    expect(bar().docked, isTrue);
    // Docked, the shape is painted, not clipped: no radius on the box.
    expect(barRadius(), BorderRadius.zero);
    expect(barShadow(), isEmpty);

    // One pill: the sheet's strip is the bar's width, one handle strip
    // tall, and reaches a hair over the bar's top edge, so the seam is
    // glass on glass.
    final strip = find
        .descendant(
          of: find.byType(DockingSheetShell),
          matching: find.byType(ClipRRect),
        )
        .first;
    final barClip = find.descendant(
      of: find.byType(FloatingNavigationBar),
      matching: find.byType(ClipRRect),
    );
    expect(
      tester.getRect(strip).left,
      closeTo(tester.getRect(barClip).left, 0.01),
    );
    expect(
      tester.getRect(strip).right,
      closeTo(tester.getRect(barClip).right, 0.01),
    );
    expect(
      tester.getRect(strip).height,
      closeTo(sheetHandleDp + sheetDockedOverlapDp, 0.01),
    );
    expect(
      tester.getRect(strip).bottom - tester.getRect(barClip).top,
      closeTo(sheetDockedOverlapDp, 0.01),
    );
    expect(
      tester.getRect(strip).bottom,
      greaterThanOrEqualTo(tester.getRect(barClip).top),
    );
    final seam = tester.getRect(barClip).top + sheetDockedOverlapDp;

    // Nothing of the sheet paints below the seam: every box in its subtree
    // that paints a colour, a shadow, a blur or a clip ends there. The
    // list's own viewport clips what it holds, and a fully faded subtree
    // paints nothing.
    final offenders = <String>[];
    void visit(RenderObject object) {
      if (object is RenderViewport ||
          (object is RenderOpacity && object.opacity == 0)) {
        return;
      }
      if (object is RenderBox && object.hasSize) {
        final paints = switch (object) {
          RenderDecoratedBox(decoration: final BoxDecoration d) =>
            (d.color != null && d.color!.a > 0) ||
                (d.boxShadow?.isNotEmpty ?? false),
          RenderPhysicalModel(:final color) => color.a > 0,
          RenderPhysicalShape(:final color) => color.a > 0,
          RenderBackdropFilter() || RenderClipRRect() => true,
          _ => false,
        };
        if (paints) {
          final rect = object.localToGlobal(Offset.zero) & object.size;
          if (rect.bottom > seam + 0.01) {
            offenders.add('${object.runtimeType} $rect');
          }
        }
      }
      object.visitChildren(visit);
    }

    visit(tester.renderObject(find.byType(DockingSheet)));
    expect(offenders, isEmpty, reason: 'below the seam at $seam');

    // Docked, the bar clips nothing round: it paints its own shape, square
    // at the top and round at the bottom, since a rounded clip with straight
    // top corners is not applied over the map's native view.
    final barClipWidget = tester.widget<ClipRRect>(barClip);
    expect(barClipWidget.borderRadius, BorderRadius.zero);
    expect(
      find.descendant(of: barClip, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: barClip, matching: find.byType(NavigationBar)),
      findsOneWidget,
    );

    // The library has no sheet: its bar is round. Back on Plan the docked
    // sheet rises to its resting height, undocking the bar as it goes.
    await _tapTab(tester, l10n.tabLibrary);
    expect(bar().docked, isFalse);
    expect(barRadius(), BorderRadius.circular(30));
    await _tapTab(tester, l10n.tabPlan);
    expect(bar().docked, isFalse);
    expect(
      tester.widget<DockingSheetShell>(find.byType(DockingSheetShell)).extent,
      closeTo(
        tester
            .widget<DraggableScrollableSheet>(
              find.byType(DraggableScrollableSheet),
            )
            .initialChildSize,
        0.001,
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the active tab follows the shell, and the Plan chrome slides '
      'away and back with it', (tester) async {
    await _pumpShell(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
    // The planner's chrome slide, whether or not its tab is showing.
    Offset plannerChromeOffset() => tester
        .widget<SlideTransition>(
          find
              .descendant(
                of: find.ancestor(
                  of: find.byType(SearchField, skipOffstage: false),
                  matching: find.byType(TabChromeSlide, skipOffstage: false),
                ),
                matching: find.byType(SlideTransition, skipOffstage: false),
              )
              .first,
        )
        .position
        .value;
    expect(container.read(activeTabProvider), plannerRoute);
    expect(plannerChromeOffset(), Offset.zero);

    await _tapTab(tester, l10n.tabRecord);
    expect(container.read(activeTabProvider), recordingRoute);
    // Off screen, the chrome is put away above the screen.
    expect(plannerChromeOffset(), const Offset(0, -1));

    await _tapTab(tester, l10n.tabLibrary);
    expect(container.read(activeTabProvider), libraryRoute);
    expect(plannerChromeOffset(), const Offset(0, -1));

    // Back on Plan it slides in over the map.
    await tester.tap(find.widgetWithText(NavigationDestination, l10n.tabPlan));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(activeTabProvider), plannerRoute);
    final midway = plannerChromeOffset();
    expect(midway.dy, greaterThan(-1));
    expect(midway.dy, lessThan(0));
    await tester.pumpAndSettle();
    expect(plannerChromeOffset(), Offset.zero);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  /// The branches painted right now, top of the stack last, by tab.
  List<TabFadeBranch> paintedBranches(WidgetTester tester) => [
    for (final b in tester.widgetList<TabFadeBranch>(
      find.byType(TabFadeBranch, skipOffstage: false),
    ))
      if (!b.offstage) b,
  ];

  /// Where the planner's chrome is on its slide: (0, -1) away, zero in.
  Offset plannerChrome(WidgetTester tester) => tester
      .widget<SlideTransition>(
        find
            .descendant(
              of: find.ancestor(
                of: find.byType(SearchField, skipOffstage: false),
                matching: find.byType(TabChromeSlide, skipOffstage: false),
              ),
              matching: find.byType(SlideTransition, skipOffstage: false),
            )
            .first,
      )
      .position
      .value;

  testWidgets('leaving Plan for Record, Plan stays painted on top while its '
      'chrome slides up and out, with no fade', (tester) async {
    await _pumpShell(tester);
    expect(plannerChrome(tester), Offset.zero);

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    // Half way: both painted at full opacity, Plan last, so on top, and its
    // chrome on its way up.
    var painted = paintedBranches(tester);
    expect(painted.map((b) => b.tab), [1, 0]);
    expect(painted.every((b) => b.opacity.value == 1), isTrue);
    expect(painted.last.leaving, isTrue);
    expect(painted.first.shown, isTrue);
    final midway = plannerChrome(tester).dy;
    expect(midway, lessThan(0));
    expect(midway, greaterThan(-1));

    await tester.pump(const Duration(milliseconds: 135));
    painted = paintedBranches(tester);
    expect(painted.map((b) => b.tab), [1]);
    await tester.pumpAndSettle();
    expect(plannerChrome(tester), const Offset(0, -1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('arriving at Plan from Record, Plan is painted on top from the '
      'first frame and its chrome slides down in', (tester) async {
    await _pumpShell(tester);
    await _tapTab(tester, l10n.tabRecord);
    expect(plannerChrome(tester), const Offset(0, -1));

    await tester.tap(find.widgetWithText(NavigationDestination, l10n.tabPlan));
    await tester.pump();
    var painted = paintedBranches(tester);
    expect(painted.map((b) => b.tab), [1, 0]);
    expect(painted.last.shown, isTrue);
    expect(painted.every((b) => b.opacity.value == 1), isTrue);
    expect(plannerChrome(tester), const Offset(0, -1));

    await tester.pump(const Duration(milliseconds: 125));
    final midway = plannerChrome(tester).dy;
    expect(midway, lessThan(0));
    expect(midway, greaterThan(-1));
    expect(paintedBranches(tester).map((b) => b.tab), [1, 0]);

    await tester.pump(const Duration(milliseconds: 135));
    expect(plannerChrome(tester), Offset.zero);
    expect(paintedBranches(tester).map((b) => b.tab), [0]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a change of tab is a short cross-fade', (tester) async {
    await _pumpShell(tester);
    List<TabFadeBranch> branches() => tester
        .widgetList<TabFadeBranch>(
          find.byType(TabFadeBranch, skipOffstage: false),
        )
        .toList();
    List<int> painted() => [
      for (var i = 0; i < branches().length; i++)
        if (!branches()[i].offstage) i,
    ];
    expect(painted(), [0]);

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabLibrary),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    // Half way: both tabs are painted, one going, one coming.
    expect(painted(), [0, 2]);
    expect(branches()[0].leaving, isTrue);
    expect(branches()[2].shown, isTrue);
    expect(branches()[0].opacity.value, inExclusiveRange(0, 1));
    expect(branches()[2].opacity.value, inExclusiveRange(0, 1));

    // The fade is over one tick after its 150 ms.
    await tester.pump(const Duration(milliseconds: 75));
    await tester.pump(const Duration(milliseconds: 16));
    expect(painted(), [2]);
    expect(branches()[2].opacity.value, 1);
    expect(find.textContaining(l10n.libraryEmpty), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  /// The control column's top on the map of [screen], painted or not.
  double controlsTopOf(WidgetTester tester, Type screen) => tester
      .widget<MapChromeInsets>(
        find
            .descendant(
              of: find.byType(screen, skipOffstage: false),
              matching: find.byType(MapChromeInsets, skipOffstage: false),
            )
            .first,
      )
      .controlsTop!;

  testWidgets('leaving Plan for Record, the one column glides up to Record\'s '
      'place on both maps and is there when Plan is dropped', (tester) async {
    await _pumpShell(tester);
    final planTop = controlsTopOf(tester, PlannerScreen);
    expect(planTop, greaterThan(defaultMapControlsTop));

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
    );
    await tester.pump();
    // Every frame of the hold: the two maps agree on the column, which is
    // on its way from Plan's place to Record's.
    var last = planTop;
    for (final step in <int>[0, 60, 65, 65]) {
      await tester.pump(Duration(milliseconds: step));
      final onPlan = controlsTopOf(tester, PlannerScreen);
      final onRecord = controlsTopOf(tester, RecordingScreen);
      expect(onRecord, onPlan);
      expect(onPlan, lessThanOrEqualTo(last));
      expect(onPlan, greaterThanOrEqualTo(defaultMapControlsTop));
      last = onPlan;
    }
    // Half way through the hold Plan is still the map on top, its column
    // between the two places.
    expect(paintedBranches(tester).map((b) => b.tab), [1, 0]);
    expect(last, lessThan(planTop));
    expect(last, greaterThan(defaultMapControlsTop));

    await tester.pump(const Duration(milliseconds: 70));
    expect(paintedBranches(tester).map((b) => b.tab), [1]);
    expect(
      controlsTopOf(tester, RecordingScreen),
      closeTo(defaultMapControlsTop, 0.5),
    );
    expect(
      controlsTopOf(tester, PlannerScreen),
      closeTo(defaultMapControlsTop, 0.5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('arriving at Plan from Record, the column glides down to '
      'Plan\'s resting place and stays there', (tester) async {
    await _pumpShell(tester);
    final planTop = controlsTopOf(tester, PlannerScreen);
    await _tapTab(tester, l10n.tabRecord);
    expect(
      controlsTopOf(tester, RecordingScreen),
      closeTo(defaultMapControlsTop, 0.5),
    );

    await tester.tap(find.widgetWithText(NavigationDestination, l10n.tabPlan));
    await tester.pump();
    expect(paintedBranches(tester).map((b) => b.tab), [1, 0]);
    expect(
      controlsTopOf(tester, PlannerScreen),
      closeTo(defaultMapControlsTop, 0.5),
    );
    await tester.pump(const Duration(milliseconds: 125));
    final midway = controlsTopOf(tester, PlannerScreen);
    expect(midway, greaterThan(defaultMapControlsTop));
    expect(midway, lessThan(planTop));
    expect(controlsTopOf(tester, RecordingScreen), midway);

    await tester.pump(const Duration(milliseconds: 135));
    expect(controlsTopOf(tester, PlannerScreen), closeTo(planTop, 0.01));
    // Where the chrome rests: the search field and the chips, measured, plus
    // the gap; and nothing moves it afterwards.
    final chrome = tester.getRect(
      find
          .ancestor(of: find.byType(SearchField), matching: find.byType(Column))
          .first,
    );
    expect(planTop, closeTo(chrome.height + 12, 0.5));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(controlsTopOf(tester, PlannerScreen), closeTo(planTop, 0.01));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('switches between all four branches', (tester) async {
    await _pumpShell(tester);

    await _tapTab(tester, l10n.tabRecord);
    expect(find.text(l10n.recordingIdleTitle), findsOneWidget);

    await _tapTab(tester, l10n.tabLibrary);
    expect(find.textContaining(l10n.libraryEmpty), findsOneWidget);

    await _tapTab(tester, l10n.tabSettings);
    // Advanced sits below the fold as the settings list grows.
    await tester.scrollUntilVisible(
      find.text(l10n.settingsServerUrls),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.settingsServerUrls), findsOneWidget);
    // The About section sits below it again, the version at its top and the
    // attribution under it — far enough apart that one scroll per line is
    // what it takes as the list grows.
    await tester.scrollUntilVisible(
      find.text('Version 0.1.0+1'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Version 0.1.0+1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(l10n.osmAttribution),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.osmAttribution), findsOneWidget);

    await _tapTab(tester, l10n.tabPlan);
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);

    // Unmount so the library's database stream can finish closing; drift
    // schedules a zero-duration timer when its last listener goes away.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('editing a server URL is stored in the overrides', (
    tester,
  ) async {
    await _pumpShell(tester);
    await _tapTab(tester, l10n.tabSettings);
    // Advanced sits below the fold as the settings list grows.
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, l10n.settingsBrouterUrl),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.enterText(
      find.widgetWithText(TextField, l10n.settingsBrouterUrl),
      'http://10.0.2.2:17777',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavigationBar));
    final container = ProviderScope.containerOf(context);
    expect(
      container.read(effectiveConfigProvider).brouterUrl,
      'http://10.0.2.2:17777',
    );
  });
}
