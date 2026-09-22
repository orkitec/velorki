import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/map/presentation/puck_ownership.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';

import '../../support/app.dart';

/// Stands in for the maplibre view: it hands out its own controller once and
/// draws the real control column over it, the way [MapControls] sits on the
/// map in the app.
class _FakeMapView extends StatefulWidget {
  const _FakeMapView({required this.onReady, required this.onCreated});

  /// The host's callback.
  final void Function(MapController controller) onReady;

  /// Tells the test which controller this map belongs to.
  final void Function(FakeMapController controller) onCreated;

  @override
  State<_FakeMapView> createState() => _FakeMapViewState();
}

class _FakeMapViewState extends State<_FakeMapView> {
  final FakeMapController controller = FakeMapController();

  @override
  void initState() {
    super.initState();
    widget.onCreated(controller);
    widget.onReady(controller);
  }

  @override
  Widget build(BuildContext context) => MapControls(controller: controller);
}

/// A builder that makes one fresh map per host and collects them in [maps].
///
/// With [onDefaultView], every map knows where it is from the start, on the
/// default view, as the real map does (it opens on the camera the store
/// holds); without, a map has no camera until something moves it.
MapViewBuilder _collectingBuilder(
  List<FakeMapController> maps, {
  bool onDefaultView = false,
}) =>
    (onReady) => _FakeMapView(
      onReady: onReady,
      onCreated: (map) {
        if (onDefaultView) {
          map
            ..center = defaultMapCamera.center
            ..zoom = defaultMapCamera.zoom
            ..bearing = 0;
        }
        maps.add(map);
      },
    );

/// Two screens with a map each, kept alive side by side the way the shell's
/// map and a detail page's are; only one is shown.
class _Tabs extends StatefulWidget {
  const _Tabs();

  static const Key plan = Key('plan-tab');
  static const Key record = Key('record-tab');

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Row(
        children: <Widget>[
          TextButton(
            onPressed: () => setState(() => _index = 0),
            child: const Text('plan'),
          ),
          TextButton(
            onPressed: () => setState(() => _index = 1),
            child: const Text('record'),
          ),
        ],
      ),
      Expanded(
        // Both maps stay alive while only one is on screen, as the shell's
        // does under a detail page's.
        child: IndexedStack(
          index: _index,
          children: <Widget>[
            KeyedSubtree(
              key: _Tabs.plan,
              child: PlannerMapHost(onMapReady: (_) {}),
            ),
            KeyedSubtree(
              key: _Tabs.record,
              child: PlannerMapHost(onMapReady: (_) {}, embedded: true),
            ),
          ],
        ),
      ),
    ],
  );
}

/// One host, plus a button that mounts a second one later.
class _LateSecondMap extends StatefulWidget {
  const _LateSecondMap();

  @override
  State<_LateSecondMap> createState() => _LateSecondMapState();
}

class _LateSecondMapState extends State<_LateSecondMap> {
  bool _second = false;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      TextButton(
        onPressed: () => setState(() => _second = true),
        child: const Text('add map'),
      ),
      SizedBox(height: 250, child: PlannerMapHost(onMapReady: (_) {})),
      if (_second)
        SizedBox(
          height: 250,
          child: PlannerMapHost(onMapReady: (_) {}, embedded: true),
        ),
    ],
  );
}

Future<Widget> _wrap(
  Widget child, {
  List<Override> overrides = const [],
  Map<String, Object> stored = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: testApp(home: Scaffold(body: child)),
  );
}

/// The CyclOSM button of the tab keyed [tab].
Finder _overlayButtonIn(Key tab) => find.descendant(
  of: find.byKey(tab),
  matching: find.widgetWithIcon(IconButton, Icons.directions_bike),
);

/// Whether the button is drawn in the accent, i.e. says the overlay is on.
bool _isHighlighted(WidgetTester tester, Finder button) =>
    tester
        .widget<IconButton>(button)
        .style
        ?.foregroundColor
        ?.resolve(const <WidgetState>{}) ==
    buildLightTheme().velorki.accent;

void main() {
  group('PlannerMapHost', () {
    testWidgets('an embedded map keeps the follow flags of its owner', (
      tester,
    ) async {
      MapChromeInsets? seen;
      var located = 0;
      var compassed = 0;
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            controlsTop: 12,
            following: true,
            headingUp: true,
            bearingDeg: 90,
            onLocate: () => located++,
            onCompass: () => compassed++,
            child: PlannerMapHost(onMapReady: (_) {}, embedded: true),
          ),
          overrides: [
            mapViewBuilderProvider.overrideWithValue(
              (_) => Builder(
                builder: (context) {
                  seen = MapChromeInsets.maybeOf(context);
                  return const SizedBox.expand();
                },
              ),
            ),
          ],
        ),
      );

      final chrome = seen!;
      // The re-wrap only takes the routing-tile button away.
      expect(chrome.showRoutingTiles, isFalse);
      expect(chrome.controlsTop, 12);
      expect(chrome.following, isTrue);
      expect(chrome.headingUp, isTrue);
      expect(chrome.bearingDeg, 90);
      chrome.onLocate!();
      expect(located, 1);
      chrome.onCompass!();
      expect(compassed, 1);
    });

    testWidgets('tells the map when the screen draws the puck itself', (
      tester,
    ) async {
      bool? owned;
      Future<void> pump({required bool ownsPosition}) async {
        await tester.pumpWidget(
          await _wrap(
            PlannerMapHost(
              onMapReady: (_) {},
              embedded: true,
              ownsPosition: ownsPosition,
            ),
            overrides: [
              mapViewBuilderProvider.overrideWithValue(
                (_) => Builder(
                  builder: (context) {
                    owned = PuckOwnership.ownedBy(context);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ],
          ),
        );
      }

      await pump(ownsPosition: false);
      expect(owned, isFalse);
      await pump(ownsPosition: true);
      expect(owned, isTrue);
    });
  });

  group('the CyclOSM overlay is one setting for every map', () {
    testWidgets('switched on in the planner, switched off in the recorder', (
      tester,
    ) async {
      final maps = <FakeMapController>[];
      await tester.pumpWidget(
        await _wrap(
          const _Tabs(),
          overrides: [
            mapViewBuilderProvider.overrideWithValue(_collectingBuilder(maps)),
          ],
        ),
      );
      await tester.pump();
      expect(maps, hasLength(2));
      final plan = maps.first;
      final record = maps.last;

      // On, on the plan tab: both maps draw it.
      await tester.tap(_overlayButtonIn(_Tabs.plan));
      await tester.pumpAndSettle();
      expect(plan.cyclosmOverlay, isTrue);
      expect(record.cyclosmOverlay, isTrue);

      // Off again, on the record tab.
      await tester.tap(find.text('record'));
      await tester.pumpAndSettle();
      expect(_isHighlighted(tester, _overlayButtonIn(_Tabs.record)), isTrue);
      await tester.tap(_overlayButtonIn(_Tabs.record));
      await tester.pumpAndSettle();

      // Back to the plan tab: the map that was never touched has dropped the
      // layer too, and its button agrees.
      await tester.tap(find.text('plan'));
      await tester.pumpAndSettle();
      expect(plan.cyclosmOverlay, isFalse);
      expect(record.cyclosmOverlay, isFalse);
      expect(_isHighlighted(tester, _overlayButtonIn(_Tabs.plan)), isFalse);
    });

    testWidgets('switched on in the recorder, switched off in the planner', (
      tester,
    ) async {
      final maps = <FakeMapController>[];
      await tester.pumpWidget(
        await _wrap(
          const _Tabs(),
          overrides: [
            mapViewBuilderProvider.overrideWithValue(_collectingBuilder(maps)),
          ],
        ),
      );
      await tester.pump();
      final plan = maps.first;
      final record = maps.last;

      await tester.tap(find.text('record'));
      await tester.pumpAndSettle();
      await tester.tap(_overlayButtonIn(_Tabs.record));
      await tester.pumpAndSettle();
      expect(record.cyclosmOverlay, isTrue);
      expect(plan.cyclosmOverlay, isTrue);

      await tester.tap(find.text('plan'));
      await tester.pumpAndSettle();
      expect(_isHighlighted(tester, _overlayButtonIn(_Tabs.plan)), isTrue);
      await tester.tap(_overlayButtonIn(_Tabs.plan));
      await tester.pumpAndSettle();

      await tester.tap(find.text('record'));
      await tester.pumpAndSettle();
      expect(record.cyclosmOverlay, isFalse);
      expect(plan.cyclosmOverlay, isFalse);
      expect(_isHighlighted(tester, _overlayButtonIn(_Tabs.record)), isFalse);
    });

    testWidgets('a map built after the toggle draws the overlay on attach', (
      tester,
    ) async {
      final maps = <FakeMapController>[];
      await tester.pumpWidget(
        await _wrap(
          const _LateSecondMap(),
          overrides: [
            mapViewBuilderProvider.overrideWithValue(_collectingBuilder(maps)),
          ],
        ),
      );
      await tester.pump();
      expect(maps, hasLength(1));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.directions_bike));
      await tester.pumpAndSettle();
      expect(maps.single.cyclosmOverlay, isTrue);

      // A screen opened afterwards brings up a map of its own.
      await tester.tap(find.text('add map'));
      await tester.pumpAndSettle();

      expect(maps, hasLength(2));
      // It was told before anything else could draw on it.
      expect(maps.last.cyclosmOverlayCalls, <bool>[true]);
      expect(maps.last.cyclosmOverlay, isTrue);
    });
  });
}
