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
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/tab_chrome_slide.dart';

import '../support/app.dart';

/// Stands in for the maplibre view: it hands out its own controller once,
/// on the default view, the way the real map opens on the stored camera.
class _FakeMapView extends StatefulWidget {
  const _FakeMapView({required this.onReady, required this.onCreated});

  final void Function(MapController controller) onReady;
  final void Function(FakeMapController controller) onCreated;

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
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFFDDDDDD));
}

/// A builder that makes one fresh map per host and collects them in [maps].
MapViewBuilder _collectingBuilder(List<FakeMapController> maps) =>
    (onReady) => _FakeMapView(onReady: onReady, onCreated: maps.add);

Future<void> _pumpShell(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
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

  /// The opacity of the list inside the sheet of [screen], painted or not.
  double listOpacityOf(WidgetTester tester, Type screen) => tester
      .widget<Opacity>(
        find
            .descendant(
              of: find.descendant(
                of: find.byType(screen, skipOffstage: false),
                matching: find.byType(DockingSheetShell, skipOffstage: false),
              ),
              matching: find.byType(Opacity, skipOffstage: false),
            )
            .first,
      )
      .opacity;

  /// The opacity of the whole Plan sheet, frame and list, painted or not:
  /// the fade wrapped directly around the sheet, not the branch's.
  double plannerSheetOpacity(WidgetTester tester) => tester
      .widgetList<FadeTransition>(
        find.byType(FadeTransition, skipOffstage: false),
      )
      .firstWhere((fade) => fade.child is DockingSheet)
      .opacity
      .value;

  /// Whether the Plan map is rendered offstage, as it is for a hold: the
  /// Offstage wrapped directly around the map host, not the branch's.
  bool plannerMapOffstage(WidgetTester tester) => tester
      .widgetList<Offstage>(find.byType(Offstage, skipOffstage: false))
      .firstWhere((offstage) => offstage.child is PlannerMapHost)
      .offstage;

  testWidgets('between Plan and Record the sheets cross-fade at once, over '
      'the Record map, with the Plan map offstage for the hold', (
    tester,
  ) async {
    // The sheets size themselves from MediaQuery: with the view agreeing
    // with the surface the resting sheet is clear of the docking range,
    // so the docking fade leaves the lists alone here.
    tester.view.physicalSize = const Size(3000, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpShell(tester);
    expect(plannerSheetOpacity(tester), 1);
    expect(plannerMapOffstage(tester), isFalse);

    // Leaving: Plan on top with its map away, its sheet fading out while
    // the Record list fades in underneath, both half way at half the hold.
    await tester.tap(
      find.widgetWithText(NavigationDestination, l10n.tabRecord),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(paintedBranches(tester).map((b) => b.tab), [1, 0]);
    expect(plannerMapOffstage(tester), isTrue);
    expect(plannerSheetOpacity(tester), closeTo(0.5, 0.12));
    expect(listOpacityOf(tester, RecordingScreen), closeTo(0.5, 0.12));

    await tester.pump(const Duration(milliseconds: 120));
    expect(paintedBranches(tester).map((b) => b.tab), [1]);
    expect(listOpacityOf(tester, RecordingScreen), 1);
    await tester.pumpAndSettle();
    expect(plannerSheetOpacity(tester), 0);
    expect(plannerMapOffstage(tester), isFalse);

    // Arriving: Plan on top from the first frame, map away and sheet
    // clear, so the Record sheet shows through; the two fade across each
    // other, and the map is back once the hold ends.
    await tester.tap(find.widgetWithText(NavigationDestination, l10n.tabPlan));
    await tester.pump();
    expect(paintedBranches(tester).map((b) => b.tab), [1, 0]);
    expect(plannerMapOffstage(tester), isTrue);
    expect(plannerSheetOpacity(tester), 0);
    expect(listOpacityOf(tester, RecordingScreen), 1);
    // Plan's tickers were off while it was away; their clock starts with
    // its first painted frame.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    expect(plannerSheetOpacity(tester), closeTo(0.5, 0.12));
    expect(listOpacityOf(tester, RecordingScreen), closeTo(0.5, 0.12));
    await tester.pump(const Duration(milliseconds: 104));
    expect(plannerMapOffstage(tester), isFalse);
    expect(plannerSheetOpacity(tester), 1);
    expect(paintedBranches(tester).map((b) => b.tab), [0]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
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
    // First frame: Plan on top, its sheet where Record's docked one is,
    // the bar square.
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

    await tester.pump(const Duration(milliseconds: 350));
    expect(
      sheetExtentOf(tester, PlannerScreen),
      closeTo(restingExtentOf(tester, PlannerScreen), 0.001),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('one control column over Plan and Record, drawn by the shell, '
      'none over the library', (tester) async {
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

  testWidgets('the zoom buttons drive the map of the tab on screen', (
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
    final plan = maps[0];

    await tester.tap(find.byTooltip(l10n.mapZoomIn));
    await tester.pump();
    expect(plan.cameraMoves.last.zoom, defaultMapCamera.zoom + 1);

    await _tapTab(tester, l10n.tabRecord);
    expect(maps, hasLength(2));
    final record = maps[1];
    final before = plan.cameraMoves.length;
    await tester.tap(find.byTooltip(l10n.mapZoomOut));
    await tester.pump();
    expect(record.cameraMoves.last.zoom, defaultMapCamera.zoom - 1);
    expect(plan.cameraMoves, hasLength(before));

    await _tapTab(tester, l10n.tabPlan);
    await tester.tap(find.byTooltip(l10n.mapZoomIn));
    await tester.pump();
    expect(plan.cameraMoves, hasLength(before + 1));

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
