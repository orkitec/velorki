import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/core/geo/track_surface.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/application/planner_map_binding.dart';
import 'package:velorki/features/planner/application/track_surface_service.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/planner/domain/route_legs.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/original_route_chip.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import 'support/fakes.dart';
import 'support/pump.dart';

late SharedPreferences _prefs;

/// A file's line: 200 points due north, about 55 m apart, with elevations.
final List<TrackPoint> _track = <TrackPoint>[
  for (var i = 0; i < 200; i++)
    TrackPoint(LatLng(48 + i * 0.0005, 11), ele: 500 + (i % 7).toDouble()),
];

/// Two named places on the line, at points 60 and 140, and one well off it.
final List<RoutePoi> _pois = <RoutePoi>[
  RoutePoi(pos: _track[60].pos, name: 'Tap', kind: PoiKind.water),
  RoutePoi(pos: _track[140].pos, name: 'Bakery', kind: PoiKind.food),
  const RoutePoi(pos: LatLng(48.05, 11.4), name: 'Castle'),
];

List<LatLng> _slice(int from, int to) => [
  for (final p in _track.sublist(from, to + 1)) p.pos,
];

SavedRoute _imported({List<SavedLeg>? legs}) => SavedRoute(
  id: 'r1',
  name: 'From a file',
  source: RouteSource.importedGpx,
  profile: RouteProfile.trekking,
  createdAt: DateTime.utc(2026, 9, 24),
  updatedAt: DateTime.utc(2026, 9, 24),
  distanceM: polylineLengthMeters([for (final p in _track) p.pos]),
  ascentM: 30,
  descentM: 30,
  bounds: BoundingBox.fromPoints(_track.map((p) => p.pos)),
  geometryBlob: PackedTrack.encode(_track),
  waypoints: [
    Waypoint(pos: _track.first.pos, kind: WaypointKind.start),
    Waypoint(pos: _track.last.pos, kind: WaypointKind.end),
  ],
  options: const RoutingOptions(),
  pois: _pois,
  legs: legs,
);

/// Answers every track with [stats] and remembers what it was asked.
class _FakeSurfaceService extends TrackSurfaceService {
  _FakeSurfaceService(this.stats)
    : super(
        local: null,
        decide: (_) => const RoutingDecision(
          source: null,
          requiredTiles: <TileName>[],
          missingTiles: <TileName>[],
        ),
      );

  final SurfaceStats stats;
  final List<List<TrackPoint>> asked = <List<TrackPoint>>[];

  @override
  Future<TrackSurface> match({
    required List<TrackPoint> points,
    required double distanceM,
  }) async {
    asked.add(points);
    return TrackSurface.matched(stats);
  }
}

const SurfaceStats _matched = SurfaceStats(
  pavedShare: 0.25,
  unpavedShare: 0.75,
  unknownShare: 0,
  cyclewayShare: 0,
  busyShare: 0,
  coveredLengthM: 11000,
  totalLengthM: 11000,
);

ProviderContainer _container(
  FakeRoutingBackend backend, {
  List<Override> overrides = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      routingBackendProvider.overrideWithValue(backend),
      sharedPreferencesProvider.overrideWithValue(_prefs),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _prefs = await SharedPreferences.getInstance();
  });
  setUp(() => _prefs.clear());

  test('an imported route opens with its ends and its named points on the '
      'track only, and the file\'s line whole, every leg of it kept', () {
    final backend = LineRoutingBackend();
    final container = _container(backend);
    container
        .read(plannerControllerProvider.notifier)
        .loadSavedRoute(_imported());

    final state = container.read(plannerControllerProvider);
    expect(state.positions, [
      _track[0].pos,
      _track[60].pos,
      _track[140].pos,
      _track[199].pos,
    ]);
    expect(state.waypoints.map((w) => w.name), [null, 'Tap', 'Bakery', null]);
    expect(state.pois.single.name, 'Castle');
    expect(state.legs.map((l) => l!.kept), [true, true, true]);
    expect(state.legs.map((l) => l!.result.positions), [
      _slice(0, 60),
      _slice(60, 140),
      _slice(140, 199),
    ]);
    expect(state.result!.geometry, _track);
    expect(backend.callCount, 0);
  });

  testWidgets('moving a point routes only its two legs; every other leg '
      'stays point for point', (tester) async {
    final backend = LineRoutingBackend();
    final container = _container(backend);
    final planner = container.read(plannerControllerProvider.notifier)
      ..loadSavedRoute(_imported());
    final before = container.read(plannerControllerProvider).legs;

    const moved = LatLng(48.03, 11.001);
    planner.moveWaypoint(1, moved);
    await _settle(tester);

    expect(backend.queries.map((q) => q.points), [
      [_track[0].pos, moved],
      [moved, _track[140].pos],
    ]);
    final state = container.read(plannerControllerProvider);
    expect(state.legs.map((l) => l!.kept), [false, false, true]);
    expect(identical(state.legs[2], before[2]), isTrue);
    final route = state.result! as PlannedRoute;
    expect(
      route.positions.sublist(route.legStarts[2]),
      _slice(140, 199),
      reason: 'the file\'s line after the change, untouched',
    );
  });

  testWidgets('inserting a point splits one leg in two, and only those two '
      'are routed', (tester) async {
    final backend = LineRoutingBackend();
    final container = _container(backend);
    const a = LatLng(48.0, 11.0);
    const b = LatLng(48.02, 11.02);
    const c = LatLng(48.04, 11.0);
    final planner = container.read(plannerControllerProvider.notifier)
      ..addWaypoint(a)
      ..addWaypoint(b)
      ..addWaypoint(c);
    await _settle(tester);
    final before = container.read(plannerControllerProvider).legs;
    backend.queries.clear();

    const x = LatLng(48.01, 11.015);
    planner.insertWaypoint(1, x);
    await _settle(tester);

    expect(backend.queries.map((q) => q.points), [
      [a, x],
      [x, b],
    ]);
    final state = container.read(plannerControllerProvider);
    expect(state.positions, [a, x, b, c]);
    expect(state.legs, hasLength(3));
    expect(identical(state.legs[2], before[1]), isTrue);
    // One line through all four, each point once.
    final line = state.result!.positions;
    expect(line, hasLength(7));
    expect([line[0], line[2], line[4], line[6]], [a, x, b, c]);
  });

  testWidgets('removing a point merges its two legs into one routed leg', (
    tester,
  ) async {
    final backend = LineRoutingBackend();
    final container = _container(backend);
    const points = [
      LatLng(48.0, 11.0),
      LatLng(48.01, 11.0),
      LatLng(48.02, 11.0),
      LatLng(48.03, 11.0),
    ];
    final planner = container.read(plannerControllerProvider.notifier);
    for (final p in points) {
      planner.addWaypoint(p);
    }
    await _settle(tester);
    final before = container.read(plannerControllerProvider).legs;
    backend.queries.clear();

    planner.removeWaypoint(2);
    await _settle(tester);

    expect(backend.queries.single.points, [points[1], points[3]]);
    final state = container.read(plannerControllerProvider);
    expect(state.legs, hasLength(2));
    expect(identical(state.legs[0], before[0]), isTrue);
  });

  testWidgets('removing a point between two of the file\'s legs keeps the '
      'file\'s line, and routes nothing', (tester) async {
    final backend = LineRoutingBackend();
    final container = _container(backend);
    container.read(plannerControllerProvider.notifier)
      ..loadSavedRoute(_imported())
      ..removeWaypoint(1);
    await _settle(tester);

    final state = container.read(plannerControllerProvider);
    expect(backend.callCount, 0);
    expect(state.legs.map((l) => l!.kept), [true, true]);
    expect(state.result!.geometry, _track);
  });

  testWidgets('switching the bike routes every leg, the file\'s own too', (
    tester,
  ) async {
    final backend = LineRoutingBackend();
    final container = _container(backend);
    container.read(plannerControllerProvider.notifier)
      ..loadSavedRoute(_imported())
      ..setProfile(RouteProfile.gravel);
    await _settle(tester);

    expect(backend.queries.map((q) => q.points), [
      [_track[0].pos, _track[60].pos],
      [_track[60].pos, _track[140].pos],
      [_track[140].pos, _track[199].pos],
    ]);
    expect(backend.queries.map((q) => q.profile), everyElement('gravel'));
    final state = container.read(plannerControllerProvider);
    expect(state.legs.map((l) => l!.kept), everyElement(isFalse));
    expect(state.hasKeptLegs, isFalse);
  });

  testWidgets('undo after each edit puts back the legs it recorded, and '
      'routes nothing', (tester) async {
    final backend = LineRoutingBackend();
    final container = _container(backend);
    final planner = container.read(plannerControllerProvider.notifier)
      ..loadSavedRoute(_imported());

    Future<void> undoes(void Function() edit) async {
      final before = container.read(plannerControllerProvider);
      edit();
      await _settle(tester);
      expect(
        container.read(plannerControllerProvider).legs,
        isNot(orderedEquals(before.legs)),
      );
      final routed = backend.callCount;

      planner.undo();
      await _settle(tester);

      final after = container.read(plannerControllerProvider);
      expect(backend.callCount, routed, reason: 'nothing routed for undo');
      expect(after.legs, hasLength(before.legs.length));
      for (var i = 0; i < before.legs.length; i++) {
        expect(identical(after.legs[i], before.legs[i]), isTrue);
      }
      expect(identical(after.result, before.result), isTrue);
      expect(after.positions, before.positions);
      expect(after.options.profile, before.options.profile);
    }

    await undoes(() => planner.moveWaypoint(1, const LatLng(48.03, 11.001)));
    await undoes(() => planner.insertWaypoint(2, const LatLng(48.05, 11.001)));
    await undoes(() => planner.removeWaypoint(2));
    await undoes(() => planner.setProfile(RouteProfile.gravel));
    await undoes(planner.reverse);
    expect(
      container.read(plannerControllerProvider).options.profile,
      RouteProfile.trekking,
    );
  });

  testWidgets('reversing rides the file\'s line backwards as it is and '
      'routes the rest again', (tester) async {
    final backend = LineRoutingBackend();
    final container = _container(backend);
    final planner = container.read(plannerControllerProvider.notifier)
      ..loadSavedRoute(_imported())
      ..moveWaypoint(1, const LatLng(48.03, 11.001));
    await _settle(tester);
    backend.queries.clear();

    planner.reverse();
    await _settle(tester);

    final state = container.read(plannerControllerProvider);
    expect(backend.queries, hasLength(2));
    expect(state.legs.map((l) => l!.kept), [true, false, false]);
    expect(
      state.legs.first!.result.positions,
      _slice(140, 199).reversed.toList(),
    );
  });

  testWidgets('a route saved with kept and routed legs opens with the same '
      'legs again', (tester) async {
    final db = VelorkiDatabase.memory();
    addTearDown(db.close);
    final repository = RouteRepository(db.routesDao);
    final backend = LineRoutingBackend();
    final container = _container(
      backend,
      overrides: [routeRepositoryProvider.overrideWithValue(repository)],
    );
    final imported = await repository.saveImportedRoute(
      name: 'From a file',
      points: _track,
      source: RouteSource.importedGpx,
      pois: _pois,
    );
    final planner = container.read(plannerControllerProvider.notifier)
      ..loadSavedRoute(imported)
      ..moveWaypoint(1, const LatLng(48.03, 11.001));
    await _settle(tester);
    var state = container.read(plannerControllerProvider);
    await repository.savePlannedRoute(
      name: imported.name,
      route: state.result!,
      waypoints: state.waypoints,
      pois: state.pois,
      options: state.options,
      id: state.savedRouteId,
    );
    final joined = state.result!.geometry;

    final reloaded = (await repository.routeById(imported.id))!;
    expect(reloaded.legs!.map((l) => l.kept), [false, false, true]);
    planner.loadSavedRoute(reloaded);
    state = container.read(plannerControllerProvider);

    expect(state.legs.map((l) => l!.kept), [false, false, true]);
    expect(state.legs.last!.result.positions, _slice(140, 199));
    expect(state.result!.geometry.map((p) => p.pos), joined.map((p) => p.pos));
    expect(state.waypoints.map((w) => w.name), [null, null, 'Bakery', null]);
  });

  group('the surface figures', () {
    testWidgets('a route with a file\'s line in it has its whole line '
        'matched, never the router\'s figures for part of it', (tester) async {
      final backend = LineRoutingBackend();
      final service = _FakeSurfaceService(_matched);
      final container = _container(
        backend,
        overrides: [trackSurfaceServiceProvider.overrideWithValue(service)],
      );
      final planner = container.read(plannerControllerProvider.notifier)
        ..loadSavedRoute(_imported());
      await tester.pump();

      expect(service.asked.single, _track);
      expect(container.read(plannerControllerProvider).surfaceStats, _matched);

      planner.moveWaypoint(1, const LatLng(48.03, 11.001));
      await _settle(tester);

      final state = container.read(plannerControllerProvider);
      expect(state.result!.messages, isEmpty);
      expect(service.asked, hasLength(2));
      expect(service.asked.last, state.result!.geometry);
      expect(state.surfaceStats, _matched);
    });

    testWidgets('a route the router drew all of takes the router\'s own', (
      tester,
    ) async {
      final backend = LineRoutingBackend();
      final service = _FakeSurfaceService(_matched);
      final container = _container(
        backend,
        overrides: [trackSurfaceServiceProvider.overrideWithValue(service)],
      );
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(const LatLng(48.0, 11.0))
        ..addWaypoint(const LatLng(48.01, 11.0))
        ..addWaypoint(const LatLng(48.02, 11.0));
      await _settle(tester);

      final state = container.read(plannerControllerProvider);
      expect(service.asked, isEmpty);
      expect(state.surfaceStats!.pavedShare, closeTo(1, 1e-9));
    });
  });

  group('the file\'s original', () {
    late VelorkiDatabase db;
    late RouteRepository repository;
    setUp(() {
      db = VelorkiDatabase.memory();
      repository = RouteRepository(db.routesDao);
    });
    tearDown(() => db.close());

    testWidgets('survives edits, a save and a reopen, and Restore brings '
        'back its exact line and markers without routing, undoably', (
      tester,
    ) async {
      final backend = LineRoutingBackend();
      final container = _container(
        backend,
        overrides: [routeRepositoryProvider.overrideWithValue(repository)],
      );
      final imported = await repository.saveImportedRoute(
        name: 'From a file',
        points: _track,
        source: RouteSource.importedGpx,
        pois: _pois,
      );
      expect(imported.original!.waypoints.map((w) => w.name), [
        null,
        'Tap',
        'Bakery',
        null,
      ]);
      final planner = container.read(plannerControllerProvider.notifier)
        ..loadSavedRoute(imported);
      final opened = container.read(plannerControllerProvider);

      // Several edits, then a save over the imported row.
      planner
        ..moveWaypoint(1, const LatLng(48.03, 11.001))
        ..addWaypoint(const LatLng(48.11, 11.0))
        ..setProfile(RouteProfile.gravel);
      await _settle(tester);
      var state = container.read(plannerControllerProvider);
      await repository.savePlannedRoute(
        name: imported.name,
        route: state.result!,
        waypoints: state.waypoints,
        pois: state.pois,
        options: state.options,
        id: state.savedRouteId,
        original: state.original,
      );
      final reloaded = (await repository.routeById(imported.id))!;
      expect(reloaded.geometry.length, isNot(_track.length));
      expect(reloaded.original!.geometry, _track);

      planner.loadSavedRoute(reloaded);
      final routed = backend.callCount;
      planner.restoreOriginal();
      await _settle(tester);

      state = container.read(plannerControllerProvider);
      expect(backend.callCount, routed, reason: 'nothing is routed');
      expect(state.result!.geometry, _track);
      expect(state.positions, opened.positions);
      expect(state.waypoints.map((w) => w.name), [null, 'Tap', 'Bakery', null]);
      expect(state.legs.map((l) => l!.kept), [true, true, true]);

      planner.undo();
      await _settle(tester);
      state = container.read(plannerControllerProvider);
      expect(backend.callCount, routed);
      expect(state.result!.geometry.length, reloaded.geometry.length);
      expect(state.positions, reloaded.waypoints.map((w) => w.pos));
    });

    test('a route imported before the original was kept takes its line '
        'as it', () {
      final container = _container(LineRoutingBackend());
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(_imported());
      final original = container.read(plannerControllerProvider).original!;
      expect(original.geometry, _track);
      expect(original.legs.map((l) => l.start), [0, 60, 140]);
    });

    test('a planned route has none, and Clear drops it', () {
      final container = _container(LineRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier)
        ..addWaypoint(const LatLng(48.0, 11.0))
        ..addWaypoint(const LatLng(48.01, 11.0));
      expect(container.read(plannerControllerProvider).original, isNull);
      planner
        ..loadSavedRoute(_imported())
        ..clear();
      expect(container.read(plannerControllerProvider).original, isNull);
      planner.undo();
      expect(container.read(plannerControllerProvider).original, isNotNull);
    });
  });

  group('the bike a file names', () {
    test('is the one its route opens with, and the one the rider picked '
        'stays theirs', () async {
      await _prefs.setString('planner.profile', 'gravel');
      final container = _container(LineRoutingBackend());
      final planner = container.read(plannerControllerProvider.notifier)
        ..loadSavedRoute(
          _imported().copyWith(
            profile: RouteProfile.mtb,
            options: const RoutingOptions(profile: RouteProfile.mtb),
          ),
        );
      expect(
        container.read(plannerControllerProvider).options.profile,
        RouteProfile.mtb,
      );
      expect(_prefs.getString('planner.profile'), 'gravel');

      // A file that names no bike opens with the one the rider rode last.
      planner.clear();
      final other = _container(LineRoutingBackend());
      other
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(_imported().copyWith(profileKnown: false));
      expect(
        other.read(plannerControllerProvider).options.profile,
        RouteProfile.gravel,
      );
    });

    test('is stored with the import, and none is stored as none', () async {
      final db = VelorkiDatabase.memory();
      addTearDown(db.close);
      final repository = RouteRepository(db.routesDao);
      final mtb = await repository.saveImportedRoute(
        name: 'MTB',
        points: _track,
        source: RouteSource.importedGpx,
        profile: RouteProfile.mtb,
      );
      final plain = await repository.saveImportedRoute(
        name: 'Plain',
        points: _track,
        source: RouteSource.importedGpx,
      );
      final mtbBack = (await repository.routeById(mtb.id))!;
      expect(mtbBack.profile, RouteProfile.mtb);
      expect(mtbBack.options.profile, RouteProfile.mtb);
      expect(mtbBack.profileKnown, isTrue);
      expect((await repository.routeById(plain.id))!.profileKnown, isFalse);
    });
  });

  group('the map\'s gestures', () {
    /// A binding over a fake map at zoom 15, where 20 pixels are some 32 m
    /// at this latitude, synced with every change of the plan.
    Future<(ProviderContainer, TestMapController, PlannerMapBinding)> bound(
      FakeRoutingBackend backend,
    ) async {
      final container = _container(backend);
      final map = TestMapController()..zoom = 15;
      final binding = PlannerMapBinding(
        map: map,
        planner: container.read(plannerControllerProvider.notifier),
      )..attach();
      await binding.sync(container.read(plannerControllerProvider));
      container.listen<PlannerState>(
        plannerControllerProvider,
        (_, next) => binding.sync(next),
      );
      return (container, map, binding);
    }

    testWidgets('a tap on the route line puts a point on it, in the leg it '
        'falls on, and routes only the two halves', (tester) async {
      final backend = LineRoutingBackend();
      final (container, map, _) = await bound(backend);
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(_imported());
      final before = container.read(plannerControllerProvider).legs;

      // Some 15 m beside point 100, between the Tap (60) and the Bakery
      // (140).
      map.onTap!(LatLng(_track[100].lat, _track[100].lon + 0.0002));
      await _settle(tester);

      final state = container.read(plannerControllerProvider);
      expect(state.waypoints, hasLength(5));
      final inserted = state.positions[2];
      expect(haversineMeters(inserted, _track[100].pos), lessThan(1));
      expect(backend.queries.map((q) => q.points), [
        [_track[60].pos, inserted],
        [inserted, _track[140].pos],
      ]);
      expect(identical(state.legs[0], before[0]), isTrue);
      expect(identical(state.legs[3], before[2]), isTrue);
    });

    testWidgets('a tap off the line adds a point at the end, and a long '
        'press anywhere is a place for the screen', (tester) async {
      final backend = LineRoutingBackend();
      final (container, map, binding) = await bound(backend);
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(_imported());
      LatLng? held;
      binding.onLongPress = (pos) => held = pos;

      // 150 m off the line: not on it.
      const off = LatLng(48.05, 11.002);
      map.onTap!(off);
      await _settle(tester);
      var state = container.read(plannerControllerProvider);
      expect(state.positions.last, off);
      expect(state.waypoints, hasLength(5));

      map.onLongPress!(_track[100].pos);
      expect(held, _track[100].pos);
      state = container.read(plannerControllerProvider);
      expect(state.waypoints, hasLength(5), reason: 'a place is no waypoint');
    });

    testWidgets('without a zoom a tap is never on the line', (tester) async {
      final backend = LineRoutingBackend();
      final (container, map, _) = await bound(backend);
      map.zoom = null;
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(_imported());
      map.onTap!(_track[100].pos);
      await _settle(tester);
      expect(
        container.read(plannerControllerProvider).positions.last,
        _track[100].pos,
      );
    });

    testWidgets('the file\'s line is drawn faint once the route differs from '
        'it, and goes with Restore and with Clear', (tester) async {
      final backend = LineRoutingBackend();
      final (container, map, _) = await bound(backend);
      final planner = container.read(plannerControllerProvider.notifier)
        ..loadSavedRoute(_imported());
      await tester.pump();
      expect(map.lines.containsKey(originalLineId), isFalse);
      expect(
        container.read(plannerControllerProvider).differsFromOriginal,
        isFalse,
      );

      planner.setProfile(RouteProfile.fastbike);
      await _settle(tester);
      expect(map.styles[originalLineId], RouteLineStyle.original);
      expect(map.lines[originalLineId], [for (final p in _track) p.pos]);
      expect(
        container.read(plannerControllerProvider).differsFromOriginal,
        isTrue,
      );

      planner.restoreOriginal();
      await _settle(tester);
      expect(map.lines.containsKey(originalLineId), isFalse);
      expect(
        container.read(plannerControllerProvider).differsFromOriginal,
        isFalse,
      );

      planner.moveWaypoint(1, const LatLng(48.03, 11.001));
      await _settle(tester);
      expect(map.lines.containsKey(originalLineId), isTrue);

      planner.clear();
      await _settle(tester);
      expect(map.lines, isEmpty);
    });

    test('a route planned here has no original to differ from', () {
      final container = _container(LineRoutingBackend());
      container.read(plannerControllerProvider.notifier)
        ..addWaypoint(const LatLng(48.0, 11.0))
        ..addWaypoint(const LatLng(48.01, 11.0));
      expect(
        container.read(plannerControllerProvider).differsFromOriginal,
        isFalse,
      );
    });
  });

  group('the chip over the map', () {
    testWidgets('shows while an imported route differs from its file, and '
        'Restore puts the file\'s route back with no routing', (tester) async {
      final h = await pumpScreen(
        tester,
        const PlannerScreen(),
        harness: PlannerHarness(backend: LineRoutingBackend()),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlannerScreen)),
      );
      container
          .read(plannerControllerProvider.notifier)
          .loadSavedRoute(_imported());
      await tester.pumpAndSettle();
      expect(find.byType(OriginalRouteChip), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, l10n.profileFastbike));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text(l10n.plannerDiffersFromFile), findsOneWidget);
      expect(h.map.lines.containsKey(originalLineId), isTrue);
      final routed = h.backend.callCount;

      await tester.tap(find.text(l10n.plannerRestoreOriginal));
      await tester.pumpAndSettle();
      expect(find.byType(OriginalRouteChip), findsNothing);
      expect(h.map.lines.containsKey(originalLineId), isFalse);
      expect(h.backend.callCount, routed);
      final state = container.read(plannerControllerProvider);
      expect(state.result!.geometry, _track);
      expect(state.legs.map((l) => l!.kept), everyElement(isTrue));

      // Restore is one step; Undo brings the edited route back, chip and all.
      container.read(plannerControllerProvider.notifier).undo();
      await tester.pumpAndSettle();
      expect(find.byType(OriginalRouteChip), findsOneWidget);
    });

    testWidgets('never shows for a route planned here', (tester) async {
      final h = await pumpScreen(
        tester,
        const PlannerScreen(),
        harness: PlannerHarness(backend: LineRoutingBackend()),
      );
      h.map.onTap!(const LatLng(48.0, 11.0));
      h.map.onTap!(const LatLng(48.01, 11.0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.profileFastbike));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(OriginalRouteChip), findsNothing);
    });
  });

  test('legs that do not fit the waypoints read as not known yet', () {
    final state = PlannerState(
      waypoints: [
        Waypoint(pos: _track.first.pos),
        Waypoint(pos: _track.last.pos),
      ],
    );
    expect(state.planLegs, [null]);
  });
}
