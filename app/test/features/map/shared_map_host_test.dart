import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/map/application/locate_on_open.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/map/presentation/puck_ownership.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';

import '../../support/app.dart';

/// Stands in for the maplibre view: hands out its controller once, from
/// its first build, and notes what the host put around it.
class _FakeMapView extends StatefulWidget {
  const _FakeMapView({required this.onReady, required this.onCreated});

  final void Function(MapController controller) onReady;
  final void Function(FakeMapController controller) onCreated;

  @override
  State<_FakeMapView> createState() => _FakeMapViewState();
}

class _FakeMapViewState extends State<_FakeMapView> {
  final FakeMapController controller = FakeMapController();

  /// What the host said on the last build.
  static bool? owned;
  static bool? hoisted;

  @override
  void initState() {
    super.initState();
    widget.onCreated(controller);
    widget.onReady(controller);
  }

  @override
  Widget build(BuildContext context) {
    owned = PuckOwnership.ownedBy(context);
    hoisted = MapChromeInsets.maybeOf(context)?.hoistedControls;
    return const SizedBox.expand();
  }
}

/// Counts what the host tells the move to the rider on opening.
class _Locate extends LocateOnOpen {
  _Locate(super.ref);

  final List<String> calls = <String>[];

  @override
  Future<bool> opened() async {
    calls.add('opened');
    return false;
  }

  @override
  void touched() => calls.add('touched');

  @override
  void paused(DateTime at) => calls.add('paused');

  @override
  Future<bool> resumed(DateTime at) async {
    calls.add('resumed');
    return false;
  }
}

/// The recorder's claim on the puck, as a test sets it.
class _Owns extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final NotifierProvider<_Owns, bool> _ownsProvider =
    NotifierProvider<_Owns, bool>(_Owns.new);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<FakeMapController> maps,
  required List<int> builds,
  List<Override> overrides = const <Override>[],
  Map<String, Object> stored = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      mapViewBuilderProvider.overrideWithValue((onReady) {
        builds.add(builds.length);
        return _FakeMapView(onReady: onReady, onCreated: maps.add);
      }),
      locateOnOpenProvider.overrideWith(_Locate.new),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: const Scaffold(body: SharedMapHost())),
    ),
  );
  return container;
}

void main() {
  testWidgets('publishes the map after the frame it came up in, with the '
      'overlay setting on it, and takes it back when it goes', (tester) async {
    final maps = <FakeMapController>[];
    final builds = <int>[];
    final container = await _pump(
      tester,
      maps: maps,
      builds: builds,
      stored: const <String, Object>{'map.cyclosm_overlay': true},
    );
    // Handed over from the map's build: published after that frame.
    expect(maps, hasLength(1));
    expect(maps.single.cyclosmOverlayCalls, <bool>[true]);
    await tester.pump();
    expect(container.read(sharedMapControllerProvider), same(maps.single));
    expect(_FakeMapViewState.hoisted, isTrue);

    // The setting changes: the map follows.
    await container.read(cyclosmOverlayProvider.notifier).set(false);
    await tester.pump();
    expect(maps.single.cyclosmOverlay, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(container.read(sharedMapControllerProvider), isNull);
  });

  testWidgets('builds the map once and keeps its element while what is '
      'around it changes', (tester) async {
    final maps = <FakeMapController>[];
    final builds = <int>[];
    final container = await _pump(
      tester,
      maps: maps,
      builds: builds,
      overrides: [
        recorderOwnsPuckProvider.overrideWith(
          (ref) => ref.watch(_ownsProvider),
        ),
      ],
    );
    await tester.pump();
    expect(builds, hasLength(1));
    expect(_FakeMapViewState.owned, isFalse);
    final state = tester.state(find.byType(_FakeMapView));

    // The recorder takes the puck: the map is told, through the same
    // element, without being built again.
    container.read(_ownsProvider.notifier).set(true);
    await tester.pump();
    expect(_FakeMapViewState.owned, isTrue);
    expect(builds, hasLength(1));
    expect(maps, hasLength(1));
    expect(tester.state(find.byType(_FakeMapView)), same(state));

    container.read(_ownsProvider.notifier).set(false);
    await tester.pump();
    expect(_FakeMapViewState.owned, isFalse);
    expect(builds, hasLength(1));
  });

  testWidgets('tells the move to the rider when the app opens, comes back, '
      'and when the map is touched', (tester) async {
    final container = await _pump(
      tester,
      maps: <FakeMapController>[],
      builds: <int>[],
    );
    await tester.pump();
    final locate = container.read(locateOnOpenProvider) as _Locate;
    expect(locate.calls, ['opened']);

    // A touch on the map itself: what the listener around it hears.
    tester
        .widget<Listener>(
          find
              .ancestor(
                of: find.byType(_FakeMapView),
                matching: find.byType(Listener),
              )
              .first,
        )
        .onPointerDown!(const PointerDownEvent());
    expect(locate.calls.last, 'touched');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(locate.calls.skip(2), ['paused', 'paused', 'paused', 'resumed']);
  });
}
