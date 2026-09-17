import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki/features/search/data/photon_client.dart';
import 'package:velorki/features/settings/data/units.dart';

import '../../../support/app.dart';
import '../../search/support/fake_http.dart';
import 'fakes.dart';

export '../../../support/units.dart' show imperialUnits, metricUnits;

/// A map view that hands out [controller] as soon as it is built.
class TestMapView extends StatefulWidget {
  /// Creates the test map view.
  const TestMapView({
    required this.controller,
    required this.onReady,
    super.key,
  });

  /// The controller handed to the screen.
  final TestMapController controller;

  /// The screen's callback.
  final void Function(MapController controller) onReady;

  @override
  State<TestMapView> createState() => _TestMapViewState();
}

class _TestMapViewState extends State<TestMapView> {
  @override
  void initState() {
    super.initState();
    widget.onReady(widget.controller);
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFFDDDDDD));
}

/// A [MapViewBuilder] that always produces [controller].
MapViewBuilder testMapViewBuilder(TestMapController controller) =>
    (onReady) => TestMapView(controller: controller, onReady: onReady);

/// Everything a planner or library widget test needs.
class PlannerHarness {
  /// Wires the fakes together.
  PlannerHarness({
    FakeRoutingBackend? backend,
    String photonBody = photonFixture,
    this.withRoutingBackend = true,
    this.withGeocoder = true,
  }) : backend = backend ?? FakeRoutingBackend(),
       photonAdapter = FakeHttpAdapter(body: photonBody),
       db = VelorkiDatabase.memory(),
       map = TestMapController();

  /// The routing server stand-in.
  final FakeRoutingBackend backend;

  /// Whether [routingBackendProvider] answers with [backend] or with `null`,
  /// which is the "no BRouter URL configured" case.
  final bool withRoutingBackend;

  /// Whether [photonClientProvider] answers with a client or with `null`,
  /// which is the "no Photon URL configured" case.
  final bool withGeocoder;

  /// The geocoder's HTTP stand-in.
  final FakeHttpAdapter photonAdapter;

  /// An in-memory database.
  final VelorkiDatabase db;

  /// The map the screens draw on.
  final TestMapController map;

  /// The overrides to hand to a [ProviderScope].
  List<Override> overrides(SharedPreferences prefs) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    // The test host says en-US, which would open every suite in miles. The
    // expectations here are written in metric, so the country says nothing
    // and a test that wants imperial overrides it itself.
    localeCountryProvider.overrideWithValue(null),
    routingBackendProvider.overrideWithValue(
      withRoutingBackend ? backend : null,
    ),
    photonClientProvider.overrideWithValue(
      withGeocoder
          ? PhotonClient('https://photon.test', dio: fakeDio(photonAdapter))
          : null,
    ),
    mapViewBuilderProvider.overrideWithValue(testMapViewBuilder(map)),
    velorkiDatabaseProvider.overrideWithValue(db),
  ];
}

/// Pumps [child] inside a localised [MaterialApp] with the harness' overrides.
Future<PlannerHarness> pumpScreen(
  WidgetTester tester,
  Widget child, {
  PlannerHarness? harness,
  List<Override> extraOverrides = const <Override>[],
  Size surfaceSize = const Size(1000, 2000),
}) async {
  final h = harness ?? PlannerHarness();
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(h.db.close);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...h.overrides(prefs), ...extraOverrides],
      child: testApp(home: child),
    ),
  );
  await tester.pump();
  expectNoClippedText(tester);
  return h;
}

/// Pumps the whole app shell at [initialLocation], for tests that navigate.
Future<PlannerHarness> pumpApp(
  WidgetTester tester, {
  String initialLocation = libraryRoute,
  PlannerHarness? harness,
  List<Override> extraOverrides = const <Override>[],
  Size surfaceSize = const Size(1000, 2000),
}) async {
  final h = harness ?? PlannerHarness();
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(h.db.close);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...h.overrides(prefs), ...extraOverrides],
      child: testRouterApp(
        routerConfig: createRouter(initialLocation: initialLocation),
      ),
    ),
  );
  await tester.pump();
  expectNoClippedText(tester);
  return h;
}

/// A dio that never reaches the network, for tests that do not care.
Dio unusedDio() => fakeDio(FakeHttpAdapter());

/// Unmounts the app and lets the database streams finish closing.
///
/// Drift schedules a zero-duration timer when the last listener of a stream
/// query goes away; without this the test framework reports it as a pending
/// timer after the tree is torn down.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
