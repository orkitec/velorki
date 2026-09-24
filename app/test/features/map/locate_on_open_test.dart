import 'dart:async';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/application/locate_on_open.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart';
import '../recording/support/fakes.dart';

/// The rider, a kilometre north of 48°/11°.
final LatLng _rider = LatLng(
  fakePosition(seconds: 0, meters: 1000).latitude,
  11,
);

const EdgeInsets _padding = EdgeInsets.fromLTRB(24, 180, 90, 420);

/// A position source whose one fix comes when the test says.
class _Source implements PositionSource {
  final Completer<geo.Position?> fix = Completer<geo.Position?>();

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) =>
      const Stream<geo.Position>.empty();

  /// What the phone holds already, if anything.
  geo.Position? held;

  @override
  Future<geo.Position?> lastKnown() async => held;

  /// The time limit the last request asked for.
  Duration? asked;

  /// The accuracy the last request asked for.
  geo.LocationAccuracy? askedAccuracy;

  /// Answers `null` once [timeLimit] is up, as the real source does.
  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
    geo.LocationAccuracy accuracy = geo.LocationAccuracy.high,
  }) {
    asked = timeLimit;
    askedAccuracy = accuracy;
    return Future.any([
      fix.future,
      Future<geo.Position?>.delayed(timeLimit, () => null),
    ]);
  }

  void arrive() => fix.complete(fakePosition(seconds: 0, meters: 1000));

  /// The live fix at [pos].
  void arriveAt(LatLng pos) => fix.complete(_at(pos, DateTime.now()));
}

/// A fix at [pos], taken at [time].
geo.Position _at(LatLng pos, DateTime time) => geo.Position(
  latitude: pos.lat,
  longitude: pos.lon,
  timestamp: time,
  accuracy: 50,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// Where the phone thinks it is: 200 m south of the rider.
final LatLng _held = LatLng(_rider.lat - 200 / 111194.9266, _rider.lon);

class _Map extends SharedMapController {
  _Map(this.map);

  final TestMapController map;

  @override
  MapController? build() => map;
}

class _Harness {
  _Harness(this.container, this.map, this.source, this.gateway, this.recorder);

  final ProviderContainer container;
  final TestMapController map;
  final _Source source;
  final FakeLocationPermissionGateway gateway;
  final FakeRecordingService recorder;

  LocateOnOpen get locate => container.read(locateOnOpenProvider);
}

Future<_Harness> _harness({
  LocationPermissionStatus permission = LocationPermissionStatus.granted,
  double zoom = 8,
  bool recording = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final map = TestMapController()..zoom = zoom;
  final source = _Source();
  final gateway = FakeLocationPermissionGateway(status: permission);
  final recorder = FakeRecordingService();
  if (recording) {
    recorder.emit(
      RecordingSnapshot(
        rideId: 'ride-1',
        status: RecordingStatus.active,
        startedAt: DateTime.utc(2026, 9, 24, 10),
        autoPaused: false,
        distanceM: 100,
        elapsed: const Duration(minutes: 1),
        moving: const Duration(minutes: 1),
        speedMps: 5,
        avgSpeedMps: 5,
        ascentM: 0,
        descentM: 0,
        lastPosition: _rider,
        accuracyM: 4,
        pointCount: 2,
        newPoints: [_rider],
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      routingBackendProvider.overrideWithValue(null),
      locationPermissionGatewayProvider.overrideWithValue(gateway),
      positionSourceProvider.overrideWithValue(source),
      sharedMapControllerProvider.overrideWith(() => _Map(map)),
      recordingServiceProvider.overrideWithValue(recorder),
    ],
  );
  addTearDown(container.dispose);
  container.read(locateOnOpenProvider).visiblePadding = () => _padding;
  return _Harness(container, map, source, gateway, recorder);
}

/// Opens the app, lets the fix come, and answers whether the map moved.
Future<bool> _open(_Harness h) async {
  final moved = h.locate.opened();
  h.source.arrive();
  return moved;
}

void main() {
  test('a cold start with the permission and no plan glides to the rider, '
      'into the visible map, zoomed in to 14 from further out', () async {
    final h = await _harness();
    expect(await _open(h), isTrue);
    expect(h.map.movedTo, _rider);
    expect(h.map.movedPadding, _padding);
    expect(h.map.zoom, locateOnOpenZoom);
  });

  test('a map at zoom 12 or closer keeps its zoom', () async {
    final h = await _harness(zoom: 12.5);
    expect(await _open(h), isTrue);
    expect(h.map.zoom, 12.5);
  });

  test('without the permission nothing moves, and nothing is asked', () async {
    final h = await _harness(permission: LocationPermissionStatus.denied);
    expect(await _open(h), isFalse);
    expect(h.map.movedTo, isNull);
    expect(h.gateway.requests, 0);
  });

  test('a plan on the Plan tab stays in view', () async {
    final h = await _harness();
    h.container
        .read(plannerControllerProvider.notifier)
        .addWaypoint(const LatLng(47, 10));
    expect(await _open(h), isFalse);
    expect(h.map.movedTo, isNull);
  });

  test('a card open on the Library tab stays in view; the Library\'s list '
      'does not', () async {
    final h = await _harness();
    h.container.read(activeTabProvider.notifier).show(libraryRoute);
    h.locate.cardOpen = () => true;
    expect(await _open(h), isFalse);

    final again = await _harness();
    again.container.read(activeTabProvider.notifier).show(libraryRoute);
    again.locate.cardOpen = () => false;
    expect(await _open(again), isTrue);
  });

  test('a ride being recorded is left to the Record tab', () async {
    final h = await _harness(recording: true);
    expect(await _open(h), isFalse);
    expect(h.map.movedTo, isNull);
  });

  test('a rider already in the visible map is not moved to', () async {
    final h = await _harness(zoom: 13);
    h.map.visibleBounds = BoundingBox(
      south: _rider.lat - 0.2,
      west: _rider.lon - 0.2,
      north: _rider.lat + 0.2,
      east: _rider.lon + 0.2,
    );
    expect(await _open(h), isFalse);

    // Under the sheet is not in view: a map whose bottom edge is just below
    // the rider has them under the sheet.
    h.map.visibleBounds = BoundingBox(
      south: _rider.lat - 0.001,
      west: _rider.lon - 0.2,
      north: _rider.lat + 0.2,
      east: _rider.lon + 0.2,
    );
    // The source already answered; the next open gets the same fix.
    expect(await h.locate.opened(), isTrue);
  });

  test('a hand on the map before the fix keeps the camera where the rider '
      'put it', () async {
    final h = await _harness();
    final moved = h.locate.opened();
    await Future<void>.delayed(Duration.zero);
    h.locate.touched();
    h.source.arrive();
    expect(await moved, isFalse);
    expect(h.map.movedTo, isNull);
  });

  testWidgets('no fix within ten seconds is no move', (tester) async {
    final h = await _harness();
    var moved = true;
    unawaited(h.locate.opened().then((m) => moved = m));
    await tester.pump(const Duration(seconds: 9));
    expect(moved, isTrue, reason: 'still waiting');
    await tester.pump(const Duration(seconds: 2));
    expect(moved, isFalse);
    expect(h.map.movedTo, isNull);
    expect(h.source.asked, locateOnOpenFixTimeout);
    expect(h.source.askedAccuracy, geo.LocationAccuracy.medium);
  });

  test('a return after half an hour moves; one after five minutes does '
      'not', () async {
    final h = await _harness();
    final away = DateTime.utc(2026, 9, 24, 8);
    h.source.arrive();

    h.locate.paused(away);
    expect(
      await h.locate.resumed(away.add(const Duration(minutes: 5))),
      isFalse,
    );
    expect(h.map.movedTo, isNull);

    h.locate.paused(away);
    expect(
      await h.locate.resumed(away.add(const Duration(minutes: 30))),
      isTrue,
    );
    expect(h.map.movedTo, _rider);
  });

  group('the position the phone already holds', () {
    testWidgets('a recent one is moved to at once, with no live fix yet', (
      tester,
    ) async {
      final h = await _harness();
      h.source.held = _at(
        _held,
        DateTime.now().subtract(const Duration(minutes: 20)),
      );
      var done = false;
      unawaited(h.locate.opened().then((_) => done = true));
      await tester.pump();
      expect(h.map.movedTo, _held);
      expect(h.map.movedPadding, _padding);
      expect(h.map.zoom, locateOnOpenZoom);
      expect(done, isFalse, reason: 'the live fix is still to come');
      await tester.pump(const Duration(seconds: 11));
      expect(done, isTrue);
    });

    test('one older than an hour is not', () async {
      final h = await _harness();
      h.source.held = _at(
        _held,
        DateTime.now().subtract(const Duration(minutes: 61)),
      );
      final moved = h.locate.opened();
      await Future<void>.delayed(Duration.zero);
      expect(h.map.movedTo, isNull);
      h.source.arriveAt(_rider);
      expect(await moved, isTrue);
      expect(h.map.movedTo, _rider);
    });

    test('a live fix within 300 m of it leaves the map still', () async {
      final h = await _harness();
      h.source.held = _at(_held, DateTime.now());
      final moved = h.locate.opened();
      await Future<void>.delayed(Duration.zero);
      h.source.arriveAt(_rider);
      expect(await moved, isTrue);
      expect(h.map.calls.where((c) => c.method == 'moveTo'), hasLength(1));
      expect(h.map.movedTo, _held);
    });

    test('a live fix further off moves the map again', () async {
      final h = await _harness();
      h.source.held = _at(
        LatLng(_rider.lat - 1000 / 111194.9266, _rider.lon),
        DateTime.now(),
      );
      final moved = h.locate.opened();
      await Future<void>.delayed(Duration.zero);
      h.source.arriveAt(_rider);
      expect(await moved, isTrue);
      expect(h.map.calls.where((c) => c.method == 'moveTo'), hasLength(2));
      expect(h.map.movedTo, _rider);
    });

    test('but not once the rider has touched the map', () async {
      final h = await _harness();
      final far = LatLng(_rider.lat - 1000 / 111194.9266, _rider.lon);
      h.source.held = _at(far, DateTime.now());
      final moved = h.locate.opened();
      await Future<void>.delayed(Duration.zero);
      h.locate.touched();
      h.source.arriveAt(_rider);
      expect(await moved, isTrue, reason: 'the first move was made');
      expect(h.map.calls.where((c) => c.method == 'moveTo'), hasLength(1));
      expect(h.map.movedTo, far);
    });
  });
}
