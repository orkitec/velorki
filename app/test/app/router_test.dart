import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/tab_fade.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/library/presentation/library_screen.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/planner/application/planner_map_binding.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/tab_chrome_slide.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../features/planner/support/pump.dart' as planner;
import '../support/app.dart';

/// Stands in for the maplibre view: it hands out its own controller once,
/// on the default view, the way the real map opens on the stored camera,
/// and counts the taps that reach it through the tabs above.
class _FakeMapView extends StatefulWidget {
  const _FakeMapView({
    required this.onReady,
    required this.onCreated,
    this.onTapped,
  });

  final void Function(MapController controller) onReady;
  final void Function(FakeMapController controller) onCreated;
  final VoidCallback? onTapped;

  @override
  State<_FakeMapView> createState() => _FakeMapViewState();
}

class _FakeMapViewState extends State<_FakeMapView> {
  final FakeMapController controller = FakeMapController()
    ..center = defaultMapCamera.center
    ..zoom = defaultMapCamera.zoom
    ..bearing = 0;

  @override
  void initState() {
    super.initState();
    widget.onCreated(controller);
    widget.onReady(controller);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTapped,
    child: const ColoredBox(color: Color(0xFFDDDDDD)),
  );
}

/// A builder that makes one fresh map per host and collects them in [maps];
/// [builds] counts how often it was asked for a map widget at all, and
/// [taps] every tap that reached a map.
MapViewBuilder _collectingBuilder(
  List<FakeMapController> maps, {
  List<int>? builds,
  List<int>? taps,
}) => (onReady) {
  builds?.add(builds.length);
  return _FakeMapView(
    onReady: onReady,
    onCreated: maps.add,
    onTapped: taps == null ? null : () => taps.add(taps.length),
  );
};

Future<void> _pumpShell(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  TargetPlatform? platform,
}) async {
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
        ...overrides,
      ],
      child: testRouterApp(
        routerConfig: createRouter(),
        theme: platform == null
            ? null
            : buildLightTheme().copyWith(platform: platform),
      ),
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

  testWidgets('leaving Plan for Record, the two cross-fade over the map for '
      'the length of the chrome slide, Plan\'s chrome sliding up and out', (
    tester,
  ) async {
    await _pumpShell(tester);
    expect(plannerChrome(tester), Offset.zero);

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Half way: both painted, Plan going on top and part way through its
    // fade, Record whole underneath, and Plan's chrome on its way up.
    var painted = paintedBranches(tester);
    expect(painted.map((b) => b.tab), [1, 0]);
    expect(painted.last.leaving, isTrue);
    expect(painted.first.shown, isTrue);
    expect(painted.last.opacity.value, inExclusiveRange(0, 1));
    expect(painted.first.opacity.value, 1);
    final midway = plannerChrome(tester).dy;
    expect(midway, lessThan(0));
    expect(midway, greaterThan(-1));

    // The fade takes the chrome's 200 ms, not the 150 of a plain change.
    await tester.pump(const Duration(milliseconds: 60));
    expect(paintedBranches(tester).map((b) => b.tab), [1, 0]);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 16));
    painted = paintedBranches(tester);
    expect(painted.map((b) => b.tab), [1]);
    await tester.pumpAndSettle();
    expect(plannerChrome(tester), const Offset(0, -1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('between Plan and Record the leaving tab fades out on top of '
      'the arriving one, which is whole underneath from the first frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpShell(tester);

    Future<void> change(String tab, int from, int to) async {
      await tester.tap(find.widgetWithText(NavigationDestination, tab));
      await tester.pump();
      var seenPartWay = false;
      for (final step in <int>[0, 40, 40, 40, 40, 39]) {
        await tester.pump(Duration(milliseconds: step));
        final painted = paintedBranches(tester);
        // The going tab is painted last, on top of the coming one.
        expect(painted.map((b) => b.tab), [to, from]);
        final going = painted.last;
        final coming = painted.first;
        expect(going.leaving, isTrue);
        expect(coming.shown, isTrue);
        // Only the going tab fades; the coming one is whole underneath, so
        // the two sheets never let the map through between them.
        expect(coming.opacity.value, 1);
        expect(going.opacity.value, inInclusiveRange(0, 1));
        if (going.opacity.value < 0.9 && going.opacity.value > 0.1) {
          seenPartWay = true;
        }
        // Both sheets are on the map through the fade.
        expect(
          find.descendant(
            of: find.byType(PlannerScreen, skipOffstage: false),
            matching: find.byType(DockingSheetShell, skipOffstage: false),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(RecordingScreen, skipOffstage: false),
            matching: find.byType(DockingSheetShell, skipOffstage: false),
          ),
          findsOneWidget,
        );
      }
      expect(
        seenPartWay,
        isTrue,
        reason: 'a frame with the going tab part way',
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(paintedBranches(tester).map((b) => b.tab), [to]);
      expect(paintedBranches(tester).single.opacity.value, 1);
    }

    await change(l10n.tabRecord, 0, 1);
    await change(l10n.tabPlan, 1, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('between Plan and the Library the leaving tab fades out on top '
      'over the map, for the length of the chrome slide', (tester) async {
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpShell(tester);

    Future<void> change(String tab, int from, int to) async {
      await tester.tap(find.widgetWithText(NavigationDestination, tab));
      await tester.pump();
      for (final step in <int>[0, 100, 60]) {
        await tester.pump(Duration(milliseconds: step));
        final painted = paintedBranches(tester);
        expect(painted.map((b) => b.tab), [to, from]);
        expect(painted.last.leaving, isTrue);
        expect(painted.last.opacity.value, inInclusiveRange(0, 1));
        expect(painted.first.shown, isTrue);
        expect(painted.first.opacity.value, 1);
      }
      // Half way through the 200 ms both are still there; a 150 ms fade
      // would be over by now.
      expect(
        paintedBranches(tester).last.opacity.value,
        inExclusiveRange(0, 1),
      );
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 16));
      expect(paintedBranches(tester).map((b) => b.tab), [to]);
      // The card is on the map like the sheets: same resting height.
      expect(find.byType(DockingSheetShell), findsOneWidget);
    }

    await change(l10n.tabLibrary, 0, 2);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(MapControls), findsOneWidget);
    await change(l10n.tabPlan, 2, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the shell builds one map, under the tabs, and keeps it '
      'through Plan, Record and back', (tester) async {
    final maps = <FakeMapController>[];
    final builds = <int>[];
    await _pumpShell(
      tester,
      overrides: [
        mapViewBuilderProvider.overrideWithValue(
          _collectingBuilder(maps, builds: builds),
        ),
      ],
    );
    expect(find.byType(SharedMapHost), findsOneWidget);
    // Under the branches, not inside either tab.
    expect(
      find.descendant(
        of: find.byType(PlannerScreen),
        matching: find.byType(SharedMapHost),
      ),
      findsNothing,
    );
    expect(maps, hasLength(1));
    expect(builds, hasLength(1));
    final element = tester.element(find.byType(SharedMapHost));
    final container = ProviderScope.containerOf(element);
    expect(container.read(sharedMapControllerProvider), same(maps.single));

    await _tapTab(tester, l10n.tabRecord);
    await _tapTab(tester, l10n.tabPlan);
    await _tapTab(tester, l10n.tabLibrary);
    await _tapTab(tester, l10n.tabPlan);
    expect(maps, hasLength(1));
    expect(builds, hasLength(1));
    expect(tester.element(find.byType(SharedMapHost)), same(element));
    expect(container.read(sharedMapControllerProvider), same(maps.single));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // Each platform's page transition wraps the tab differently; a touch has
  // to fall through both.
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('a tap on the map, beside a tab\'s chrome and above its '
        'sheet, falls through the tab to the shell\'s map on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(3000, 6000);
      addTearDown(tester.view.resetPhysicalSize);
      final maps = <FakeMapController>[];
      final taps = <int>[];
      await _pumpShell(
        tester,
        platform: platform,
        overrides: [
          mapViewBuilderProvider.overrideWithValue(
            _collectingBuilder(maps, taps: taps),
          ),
        ],
      );
      // Well below the search field and the chips, left of the control
      // column, above the sheet.
      final sheetTop = tester.getTopLeft(find.byType(DockingSheetShell)).dy;
      final chromeBottom = tester.getBottomLeft(find.byType(SearchField)).dy;
      final spot = Offset(60, (chromeBottom + sheetTop) / 2);
      await tester.tapAt(spot);
      await tester.pump();
      expect(taps, hasLength(1));

      await _tapTab(tester, l10n.tabRecord);
      await tester.tapAt(spot);
      await tester.pump();
      expect(taps, hasLength(2));

      // The sheet keeps its own taps.
      await tester.tapAt(tester.getCenter(find.byType(SheetHandle)));
      await tester.pump();
      expect(taps, hasLength(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  testWidgets('on a small screen the control column reaches down over the '
      'Plan sheet, and the sheet wins: a tap where the two share pixels is '
      'the sheet\'s, not the column\'s', (tester) async {
    await _pumpShell(tester);
    // An iPhone SE: 375 by 667 logical pixels.
    tester.view.physicalSize = const Size(375, 667);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.binding.setSurfaceSize(const Size(375, 667));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(DockingSheetShell));
    final column = tester.getRect(find.byType(MapControls));
    // The case this guards: the column's foot is under the resting sheet.
    // Where exactly the sheet's buttons fall depends on the language's line
    // breaks, so the point tested is the middle of the overlap itself.
    final shared = column.intersect(sheet);
    expect(shared.isEmpty, isFalse, reason: 'column $column sheet $sheet');

    final hits = HitTestResult();
    tester.binding.hitTestInView(hits, shared.center, tester.view.viewId);
    final targets = hits.path.map((e) => e.target).toSet();
    expect(
      targets,
      contains(tester.renderObject(find.byType(DockingSheetShell))),
    );
    expect(
      targets,
      isNot(contains(tester.renderObject(find.byType(MapControls)))),
    );

    // Above the sheet the column still takes its taps: the top of its
    // first button.
    final sheetTop = tester.getTopLeft(find.byType(DockingSheetShell)).dy;
    final aboveSheet = Offset(column.center.dx, column.top + 12);
    expect(aboveSheet.dy, lessThan(sheetTop));
    final columnHits = HitTestResult();
    tester.binding.hitTestInView(columnHits, aboveSheet, tester.view.viewId);
    expect(
      columnHits.path.map((e) => e.target),
      contains(tester.renderObject(find.byType(MapControls))),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('each tab draws its own layers on the shared map while it is '
      'on screen and takes them off when it leaves', (tester) async {
    final h = await planner.pumpApp(tester, initialLocation: plannerRoute);
    await tester.pumpAndSettle();
    final map = h.map;

    // A plan on the Plan tab: two markers and the main line.
    map.onTap!(const LatLng(48.0, 11.0));
    await tester.pump();
    map.onTap!(const LatLng(48.1, 11.1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(map.waypoints, hasLength(2));
    expect(map.lines[mainRouteLineId], isNotNull);
    final route = map.lines[mainRouteLineId]!;
    expect(map.lines[followedRouteLineId], isNull);

    // Record comes up: the plan's markers and line go, and Record draws
    // the same route as the one to ride, in its own line.
    await _tapTab(tester, l10n.tabRecord);
    expect(map.waypoints, isEmpty);
    expect(map.lines[mainRouteLineId], isNull);
    expect(map.lines[followedRouteLineId], route);
    expect(map.onWaypointDragged, isNull);
    expect(map.onWaypointTapped, isNull);
    expect(map.onTap, isNull);

    // Back on Plan: Record's line goes, the plan is back, and taps plan.
    await _tapTab(tester, l10n.tabPlan);
    expect(map.lines[followedRouteLineId], isNull);
    expect(map.waypoints, hasLength(2));
    expect(map.lines[mainRouteLineId], route);
    expect(map.onTap, isNotNull);
    expect(map.onWaypointDragged, isNotNull);

    await planner.unmountApp(tester);
  });

  /// The extent of the sheet of [screen], painted or not.
  double sheetExtentOf(WidgetTester tester, Type screen) => tester
      .widget<DockingSheetShell>(
        find
            .descendant(
              of: find.byType(screen, skipOffstage: false),
              matching: find.byType(DockingSheetShell, skipOffstage: false),
            )
            .first,
      )
      .extent;

  /// The smallest extent of the sheet of [screen]: docked.
  double dockedExtentOf(WidgetTester tester, Type screen) => tester
      .widget<DraggableScrollableSheet>(
        find
            .descendant(
              of: find.byType(screen, skipOffstage: false),
              matching: find.byType(
                DraggableScrollableSheet,
                skipOffstage: false,
              ),
            )
            .first,
      )
      .minChildSize;

  /// The resting extent of the sheet of [screen].
  double restingExtentOf(WidgetTester tester, Type screen) => tester
      .widget<DraggableScrollableSheet>(
        find
            .descendant(
              of: find.byType(screen, skipOffstage: false),
              matching: find.byType(
                DraggableScrollableSheet,
                skipOffstage: false,
              ),
            )
            .first,
      )
      .initialChildSize;

  /// Pulls the sheet of the tab on screen all the way down.
  Future<void> dockSheet(WidgetTester tester) async {
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 1500),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Plan docked, tapping Record: the Record sheet is docked from '
      'the first frame and rises at once, the bar round with it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpShell(tester);
    bool barDocked() => tester
        .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
        .docked;
    await dockSheet(tester);
    expect(barDocked(), isTrue);
    final docked = dockedExtentOf(tester, PlannerScreen);

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
    );
    await tester.pump();
    // First frame: the Record sheet, new, is where Plan's docked one is.
    expect(sheetExtentOf(tester, RecordingScreen), closeTo(docked, 0.001));
    // Its rise starts after that frame; the clock runs from the first
    // painted tick.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    final rising = sheetExtentOf(tester, RecordingScreen);
    expect(rising, greaterThan(docked + 0.005));
    expect(rising, lessThan(restingExtentOf(tester, RecordingScreen) - 0.005));
    expect(barDocked(), isFalse);
    // The Plan sheet, fading out underneath, stays docked where it was
    // rather than jumping anywhere first.
    expect(sheetExtentOf(tester, PlannerScreen), closeTo(docked, 0.001));
    await tester.pump(const Duration(milliseconds: 50));
    expect(sheetExtentOf(tester, PlannerScreen), closeTo(docked, 0.001));

    await tester.pump(const Duration(milliseconds: 400));
    expect(
      sheetExtentOf(tester, RecordingScreen),
      closeTo(restingExtentOf(tester, RecordingScreen), 0.001),
    );
    expect(barDocked(), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Record docked, tapping Plan: the Plan sheet starts where '
      'Record\'s docked one is and rises at once, undocking the bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpShell(tester);
    bool barDocked() => tester
        .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
        .docked;
    await _tapTab(tester, l10n.tabRecord);
    await dockSheet(tester);
    expect(barDocked(), isTrue);
    final docked = dockedExtentOf(tester, RecordingScreen);

    await tester.tap(find.widgetWithText(NavigationDestination, l10n.tabPlan));
    await tester.pump();
    // First frame: Plan's sheet is where Record's docked one is, the bar
    // square.
    expect(sheetExtentOf(tester, PlannerScreen), closeTo(docked, 0.001));
    expect(barDocked(), isTrue);

    // Plan's tickers were off while it was away; the rise's clock runs
    // from its first painted tick.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 134));
    final rising = sheetExtentOf(tester, PlannerScreen);
    expect(rising, greaterThan(docked + 0.005));
    expect(rising, lessThan(restingExtentOf(tester, PlannerScreen) - 0.005));
    expect(barDocked(), isFalse);
    // Record's sheet, fading out underneath, stays docked.
    expect(sheetExtentOf(tester, RecordingScreen), closeTo(docked, 0.001));

    await tester.pump(const Duration(milliseconds: 350));
    expect(
      sheetExtentOf(tester, PlannerScreen),
      closeTo(restingExtentOf(tester, PlannerScreen), 0.001),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('one control column over Plan, Record and the Library, drawn '
      'by the shell, none over the settings', (tester) async {
    await _pumpShell(tester);
    expect(find.byType(MapControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PlannerScreen),
        matching: find.byType(MapControls),
      ),
      findsNothing,
    );
    expect(find.byTooltip(l10n.offlineEntryTitle), findsOneWidget);

    await _tapTab(tester, l10n.tabRecord);
    expect(find.byType(MapControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RecordingScreen),
        matching: find.byType(MapControls),
      ),
      findsNothing,
    );
    expect(find.byTooltip(l10n.offlineEntryTitle), findsNothing);

    await _tapTab(tester, l10n.tabLibrary);
    expect(find.byType(MapControls), findsOneWidget);
    expect(find.byTooltip(l10n.offlineEntryTitle), findsNothing);

    await _tapTab(tester, l10n.tabSettings);
    expect(find.byType(MapControls), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the column shrinks and grows for the download button as the '
      'tab changes, rather than jumping', (tester) async {
    await _pumpShell(tester);
    final onPlan = tester.getSize(find.byType(MapControls)).height;

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midway = tester.getSize(find.byType(MapControls)).height;
    await tester.pumpAndSettle();
    final onRecord = tester.getSize(find.byType(MapControls)).height;
    expect(onRecord, lessThan(onPlan - 30));
    expect(midway, lessThan(onPlan));
    expect(midway, greaterThan(onRecord));

    await tester.tap(find.widgetWithText(NavigationDestination, l10n.tabPlan));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final back = tester.getSize(find.byType(MapControls)).height;
    expect(back, greaterThan(onRecord));
    expect(back, lessThan(onPlan));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MapControls)).height, onPlan);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the zoom buttons drive the one shared map from either tab', (
    tester,
  ) async {
    final maps = <FakeMapController>[];
    await _pumpShell(
      tester,
      overrides: [
        mapViewBuilderProvider.overrideWithValue(_collectingBuilder(maps)),
      ],
    );
    expect(maps, hasLength(1));
    final map = maps.single;

    await tester.tap(find.byTooltip(l10n.mapZoomIn));
    await tester.pump();
    expect(map.cameraMoves.last.zoom, defaultMapCamera.zoom + 1);

    await _tapTab(tester, l10n.tabRecord);
    expect(maps, hasLength(1));
    await tester.tap(find.byTooltip(l10n.mapZoomOut));
    await tester.pump();
    expect(map.cameraMoves.last.zoom, defaultMapCamera.zoom);

    await _tapTab(tester, l10n.tabPlan);
    await tester.tap(find.byTooltip(l10n.mapZoomIn));
    await tester.pump();
    expect(map.cameraMoves.last.zoom, defaultMapCamera.zoom + 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('arriving at Plan from Record, Plan fades in from the first '
      'frame and its chrome slides down in', (tester) async {
    await _pumpShell(tester);
    await _tapTab(tester, l10n.tabRecord);
    expect(plannerChrome(tester), const Offset(0, -1));

    await tester.tap(find.widgetWithText(NavigationDestination, l10n.tabPlan));
    await tester.pump();
    final painted = paintedBranches(tester);
    expect(painted.map((b) => b.tab), [0, 1]);
    expect(painted.first.shown, isTrue);
    expect(painted.last.leaving, isTrue);
    expect(plannerChrome(tester), const Offset(0, -1));

    await tester.pump(const Duration(milliseconds: 125));
    final midway = plannerChrome(tester).dy;
    expect(midway, lessThan(0));
    expect(midway, greaterThan(-1));
    expect(paintedBranches(tester).map((b) => b.tab), [0, 1]);

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
      for (final b in branches())
        if (!b.offstage) b.tab,
    ]..sort();
    expect(painted(), [0]);

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabSettings),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    // Half way: both tabs are painted, the going one last, on top, part
    // way through its fade; the coming one whole underneath.
    expect(painted(), [0, 3]);
    expect(branches().map((b) => b.tab), [1, 2, 3, 0]);
    expect(branches().last.leaving, isTrue);
    expect(branches().last.opacity.value, inExclusiveRange(0, 1));
    final coming = branches().singleWhere((b) => b.tab == 3);
    expect(coming.shown, isTrue);
    expect(coming.opacity.value, 1);

    // The fade is over one tick after its 150 ms.
    await tester.pump(const Duration(milliseconds: 75));
    await tester.pump(const Duration(milliseconds: 16));
    expect(painted(), [3]);
    expect(branches().singleWhere((b) => b.tab == 3).opacity.value, 1);
    expect(find.text(l10n.tabSettings), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  /// Where the shell's one control column sits below the top of the screen
  /// (no safe area in a test), which is the glide's value.
  double columnTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(MapControls)).dy;

  testWidgets('leaving Plan for Record, the one column glides up to Record\'s '
      'place and is there when Plan is dropped', (tester) async {
    await _pumpShell(tester);
    final planTop = columnTop(tester);
    expect(planTop, greaterThan(defaultMapControlsTop));

    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
    );
    await tester.pump();
    // Every frame of the fade the column is on its way from Plan's place
    // to Record's, never back.
    var last = planTop;
    for (final step in <int>[0, 60, 65, 65]) {
      await tester.pump(Duration(milliseconds: step));
      final top = columnTop(tester);
      expect(top, lessThanOrEqualTo(last));
      expect(top, greaterThanOrEqualTo(defaultMapControlsTop));
      last = top;
    }
    // Most of the way through the fade both tabs are still painted and the
    // column is between the two places.
    expect(paintedBranches(tester).map((b) => b.tab), [1, 0]);
    expect(last, lessThan(planTop));
    expect(last, greaterThan(defaultMapControlsTop));

    await tester.pump(const Duration(milliseconds: 70));
    expect(paintedBranches(tester).map((b) => b.tab), [1]);
    expect(columnTop(tester), closeTo(defaultMapControlsTop, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('arriving at Plan from Record, the column glides down to '
      'Plan\'s resting place and stays there', (tester) async {
    await _pumpShell(tester);
    final planTop = columnTop(tester);
    await _tapTab(tester, l10n.tabRecord);
    expect(columnTop(tester), closeTo(defaultMapControlsTop, 0.5));

    await tester.tap(find.widgetWithText(NavigationDestination, l10n.tabPlan));
    await tester.pump();
    expect(paintedBranches(tester).map((b) => b.tab), [0, 1]);
    expect(columnTop(tester), closeTo(defaultMapControlsTop, 0.5));
    await tester.pump(const Duration(milliseconds: 125));
    final midway = columnTop(tester);
    expect(midway, greaterThan(defaultMapControlsTop));
    expect(midway, lessThan(planTop));

    await tester.pump(const Duration(milliseconds: 135));
    expect(columnTop(tester), closeTo(planTop, 0.01));
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
      expect(columnTop(tester), closeTo(planTop, 0.01));
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
