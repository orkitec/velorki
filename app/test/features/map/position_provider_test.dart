import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../recording/support/fakes.dart';

geo.Position _fix({
  double accuracy = 0,
  double heading = 0,
  double speed = 0,
  bool flags = false,
}) => geo.Position(
  latitude: 40.8153,
  longitude: -73.9645,
  timestamp: DateTime.utc(2026),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
  hasAccuracy: flags,
  hasHeading: flags,
  hasSpeed: flags,
);

geo.Position _fixAt(double latitude, {int second = 0}) => geo.Position(
  latitude: latitude,
  longitude: 11,
  timestamp: DateTime.utc(2026, 9, 12, 10, 0, second),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  hasAccuracy: true,
);

/// A [PositionSource] whose cached fix and live stream a test decides.
class ScriptedPositionSource implements PositionSource {
  final StreamController<geo.Position> _positions =
      StreamController<geo.Position>.broadcast();

  /// The settings every subscription asked for.
  final List<geo.LocationSettings> settings = <geo.LocationSettings>[];

  /// What [lastKnown] and [current] answer.
  geo.Position? cached;

  /// Pushes a fix to whoever subscribed.
  void emit(geo.Position position) => _positions.add(position);

  /// Breaks the live stream, as a revoked permission does.
  void fail(Object error) => _positions.addError(error);

  /// Whether the GPS stream is being listened to.
  bool get isStreaming => _positions.hasListener;

  @override
  Stream<geo.Position> positions(geo.LocationSettings locationSettings) {
    settings.add(locationSettings);
    return _positions.stream;
  }

  @override
  Future<geo.Position?> lastKnown() async => cached;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) async => cached;

  /// Closes the stream.
  Future<void> close() =>
      _positions.isClosed ? Future<void>.value() : _positions.close();
}

void main() {
  group('MapPosition.measuredValue', () {
    test('takes a flagged value as it stands, zero included', () {
      expect(MapPosition.measuredValue(0, flagged: true), 0);
      expect(MapPosition.measuredValue(12.5, flagged: true), 12.5);
    });

    test('falls back to a non-zero value when the flag is clear', () {
      // geolocator_android drops the has* flags, so an unflagged 28.4° course
      // is still a course.
      expect(MapPosition.measuredValue(28.4, flagged: false), 28.4);
      expect(MapPosition.measuredValue(0, flagged: false), isNull);
    });

    test('rejects a value that is not a number', () {
      expect(MapPosition.measuredValue(double.nan, flagged: true), isNull);
      expect(MapPosition.measuredValue(double.infinity, flagged: true), isNull);
    });
  });

  group('MapPosition.fromGeolocator', () {
    test('keeps accuracy, course and speed an Android fix never flags', () {
      final position = MapPosition.fromGeolocator(
        _fix(accuracy: 5, heading: 28.4, speed: 4.2),
      );

      expect(position.position, const LatLng(40.8153, -73.9645));
      expect(position.accuracyM, 5);
      expect(position.headingDeg, 28.4);
      expect(position.speedMps, 4.2);
    });

    test('reports no course and no speed when nothing measured any', () {
      final position = MapPosition.fromGeolocator(_fix());

      expect(position.accuracyM, 0);
      expect(position.headingDeg, isNull);
      expect(position.speedMps, isNull);
    });

    test('keeps a flagged zero, e.g. a course of due north', () {
      final position = MapPosition.fromGeolocator(
        _fix(accuracy: 5, speed: 3, flags: true),
      );

      expect(position.headingDeg, 0);
    });
  });

  group('mapLocationSettings', () {
    test('trades a fix per second for five metres of movement', () {
      expect(mapLocationSettings.accuracy, geo.LocationAccuracy.high);
      expect(mapLocationSettings.distanceFilter, 5);
    });
  });

  group('MapPosition', () {
    test('two fixes of the same moment are the same position', () {
      final one = MapPosition.fromGeolocator(_fixAt(48));
      final same = MapPosition.fromGeolocator(_fixAt(48));
      final elsewhere = MapPosition.fromGeolocator(_fixAt(49));

      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(one, isNot(elsewhere));
    });

    test('toString names the spot and its accuracy', () {
      final position = MapPosition(
        position: const LatLng(48.0, 11.0),
        accuracyM: 5,
        timestamp: DateTime.utc(2026, 9, 12, 10),
      );

      expect(position.toString(), 'MapPosition(LatLng(48.0, 11.0), ±5.0m)');
    });
  });

  group('GeolocatorPositionSource', () {
    late FakeGeolocatorPlatform platform;
    const source = GeolocatorPositionSource();

    setUp(() {
      platform = FakeGeolocatorPlatform();
      geo.GeolocatorPlatform.instance = platform;
    });

    tearDown(() => platform.close());

    test('hands back the fix the OS had cached', () async {
      platform.cachedPosition = _fixAt(48);

      expect((await source.lastKnown())?.latitude, 48);
    });

    test('an OS with nothing cached reports no fix', () async {
      expect(await source.lastKnown(), isNull);
    });

    test('a fresh fix is asked for with the map accuracy', () async {
      platform.freshPosition = _fixAt(48);

      expect(
        (await source.current(timeLimit: const Duration(seconds: 3)))?.latitude,
        48,
      );
      final asked = platform.settings.single;
      expect(asked?.accuracy, geo.LocationAccuracy.high);
      expect(asked?.distanceFilter, 5);
      expect(asked?.timeLimit, const Duration(seconds: 3));
    });

    test('ten seconds is long enough to wait for a fresh fix', () async {
      platform.freshPosition = _fixAt(48);

      await source.current();

      expect(platform.settings.single?.timeLimit, const Duration(seconds: 10));
    });

    test('a fresh fix that never arrives is reported as no fix', () async {
      // The caller falls back to the last known position instead of seeing a
      // TimeoutException from the map screen.
      platform.currentError = TimeoutException('no fix in time');

      expect(await source.current(), isNull);
    });

    test('a location service switched off mid-request is no fix', () async {
      platform.currentError = const geo.LocationServiceDisabledException();

      expect(await source.current(), isNull);
    });

    test('the live stream is subscribed with the settings given', () async {
      final fixes = <geo.Position>[];
      final subscription = source
          .positions(mapLocationSettings)
          .listen(fixes.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      platform.emit(_fixAt(48));
      await pumpEventQueue();

      expect(fixes.single.latitude, 48);
      expect(platform.settings.single, same(mapLocationSettings));
    });
  });

  group('devicePositionProvider', () {
    late ScriptedPositionSource source;
    late FakeLocationPermissionGateway permission;

    setUp(() {
      source = ScriptedPositionSource();
      permission = FakeLocationPermissionGateway();
      addTearDown(source.close);
    });

    ProviderContainer containerFor(LocationPermissionStatus status) {
      permission.status = status;
      final container = ProviderContainer(
        overrides: [
          locationPermissionGatewayProvider.overrideWithValue(permission),
          positionSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('reports no position while the permission is missing', () async {
      final container = containerFor(LocationPermissionStatus.denied);
      final subscription = container.listen(devicePositionProvider, (_, _) {});
      addTearDown(subscription.close);

      await pumpEventQueue();

      final state = container.read(devicePositionProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, isNull);
      // Nothing may start the GPS before the permission is there.
      expect(source.isStreaming, isFalse);
    });

    test('shows the cached fix before the first live one', () async {
      source.cached = _fixAt(48);
      final container = containerFor(LocationPermissionStatus.granted);
      final seen = <MapPosition?>[];
      final subscription = container.listen(devicePositionProvider, (_, next) {
        if (next.hasValue) seen.add(next.value);
      });
      addTearDown(subscription.close);
      await pumpEventQueue();

      expect(seen.single?.position, const LatLng(48.0, 11.0));

      source.emit(_fixAt(48.5, second: 1));
      await pumpEventQueue();

      expect(seen.last?.position, const LatLng(48.5, 11.0));
      expect(seen, hasLength(2));
    });

    test('waits for the first live fix when nothing was cached', () async {
      final container = containerFor(LocationPermissionStatus.granted);
      final subscription = container.listen(devicePositionProvider, (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();

      expect(container.read(devicePositionProvider).isLoading, isTrue);
      expect(source.isStreaming, isTrue);

      source.emit(_fixAt(48));
      await pumpEventQueue();

      expect(
        container.read(devicePositionProvider).value?.position,
        const LatLng(48.0, 11.0),
      );
    });

    test('subscribes with the map location settings', () async {
      final container = containerFor(LocationPermissionStatus.granted);
      final subscription = container.listen(devicePositionProvider, (_, _) {});
      addTearDown(subscription.close);

      await pumpEventQueue();

      expect(source.settings.single, same(mapLocationSettings));
    });

    test('a failing GPS stream comes through as an error', () async {
      final container = containerFor(LocationPermissionStatus.granted);
      final subscription = container.listen(
        devicePositionProvider,
        (_, _) {},
        onError: (_, _) {},
      );
      addTearDown(subscription.close);
      await pumpEventQueue();

      source.fail(StateError('location service died'));
      await pumpEventQueue();

      final state = container.read(devicePositionProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
    });

    test('a permission granted later starts the GPS', () async {
      source.cached = _fixAt(48);
      final container = containerFor(LocationPermissionStatus.denied);
      final subscription = container.listen(devicePositionProvider, (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();
      expect(source.isStreaming, isFalse);

      permission.status = LocationPermissionStatus.granted;
      await container
          .read(locationPermissionControllerProvider.notifier)
          .refresh();
      await pumpEventQueue();

      expect(source.isStreaming, isTrue);
      expect(
        container.read(devicePositionProvider).value?.position,
        const LatLng(48.0, 11.0),
      );
    });

    test('the GPS is let go when the last listener goes away', () async {
      final container = containerFor(LocationPermissionStatus.granted);
      final subscription = container.listen(devicePositionProvider, (_, _) {});
      await pumpEventQueue();
      expect(source.isStreaming, isTrue);

      subscription.close();
      await pumpEventQueue();

      expect(source.isStreaming, isFalse);
    });
  });
}
