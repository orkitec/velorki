import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/core/permissions/location_permission.dart';

import '../../features/recording/support/fakes.dart';

/// A gateway that is denied until the system prompt is shown, and granted
/// afterwards — the happy path of a first launch.
class GrantOnPromptGateway extends FakeLocationPermissionGateway {
  /// Creates the gateway, denied to begin with.
  GrantOnPromptGateway() : super(status: LocationPermissionStatus.denied);

  @override
  Future<LocationPermissionStatus> request() async {
    await super.request();
    return status = LocationPermissionStatus.granted;
  }
}

ProviderContainer _containerWith(LocationPermissionGateway gateway) {
  final container = ProviderContainer(
    overrides: [locationPermissionGatewayProvider.overrideWithValue(gateway)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('LocationPermissionStatus', () {
    test('only a granted permission lets a position stream start', () {
      expect(LocationPermissionStatus.granted.isUsable, isTrue);
      expect(LocationPermissionStatus.denied.isUsable, isFalse);
      expect(LocationPermissionStatus.deniedForever.isUsable, isFalse);
      expect(LocationPermissionStatus.serviceDisabled.isUsable, isFalse);
    });

    test('only a plain denial is worth asking about again', () {
      expect(LocationPermissionStatus.denied.canAsk, isTrue);
      expect(LocationPermissionStatus.granted.canAsk, isFalse);
      // A permanent denial and a switched-off location service both need the
      // settings, not another prompt.
      expect(LocationPermissionStatus.deniedForever.canAsk, isFalse);
      expect(LocationPermissionStatus.serviceDisabled.canAsk, isFalse);
    });
  });

  group('GeolocatorLocationPermissionGateway', () {
    late FakeGeolocatorPlatform platform;
    const gateway = GeolocatorLocationPermissionGateway();

    setUp(() {
      platform = FakeGeolocatorPlatform();
      geo.GeolocatorPlatform.instance = platform;
    });

    tearDown(() => platform.close());

    test('a switched-off location service outranks the permission', () async {
      platform
        ..serviceEnabled = false
        ..permission = geo.LocationPermission.whileInUse;

      expect(await gateway.check(), LocationPermissionStatus.serviceDisabled);
      // No point asking the OS about a permission that cannot be used.
      expect(platform.checks, 0);
    });

    test('while in use and always both count as granted', () async {
      platform.permission = geo.LocationPermission.whileInUse;
      expect(await gateway.check(), LocationPermissionStatus.granted);

      platform.permission = geo.LocationPermission.always;
      expect(await gateway.check(), LocationPermissionStatus.granted);
    });

    test('a permanent denial is kept apart from a plain one', () async {
      platform.permission = geo.LocationPermission.deniedForever;
      expect(await gateway.check(), LocationPermissionStatus.deniedForever);

      platform.permission = geo.LocationPermission.denied;
      expect(await gateway.check(), LocationPermissionStatus.denied);
    });

    test('a status the plugin cannot determine reads as denied', () async {
      // The web plugin answers this when the browser has no Permission API;
      // a prompt is still worth showing.
      platform.permission = geo.LocationPermission.unableToDetermine;

      expect(await gateway.check(), LocationPermissionStatus.denied);
    });

    test('asking never shows a prompt while the service is off', () async {
      platform
        ..serviceEnabled = false
        ..promptAnswer = geo.LocationPermission.whileInUse;

      expect(await gateway.request(), LocationPermissionStatus.serviceDisabled);
      expect(platform.prompts, 0);
    });

    test('the prompt answer is mapped the same way as a check', () async {
      platform
        ..permission = geo.LocationPermission.denied
        ..promptAnswer = geo.LocationPermission.deniedForever;

      expect(await gateway.request(), LocationPermissionStatus.deniedForever);
      expect(platform.prompts, 1);
    });

    test('both settings pages are opened through the plugin', () async {
      expect(await gateway.openAppSettings(), isTrue);
      expect(platform.openedAppSettings, isTrue);

      expect(await gateway.openLocationSettings(), isTrue);
      expect(platform.openedLocationSettings, isTrue);
    });

    test('a settings page the platform refuses to open says so', () async {
      platform.settingsOpen = false;

      expect(await gateway.openAppSettings(), isFalse);
      expect(await gateway.openLocationSettings(), isFalse);
    });
  });

  group('locationPermissionGatewayProvider', () {
    test('is wired to geolocator unless a test says otherwise', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(locationPermissionGatewayProvider),
        isA<GeolocatorLocationPermissionGateway>(),
      );
    });
  });

  group('LocationPermissionController', () {
    test('starts out with whatever the gateway reports', () async {
      final gateway = FakeLocationPermissionGateway(
        status: LocationPermissionStatus.denied,
      );
      final container = _containerWith(gateway);

      expect(
        await container.read(locationPermissionControllerProvider.future),
        LocationPermissionStatus.denied,
      );
      // Building the controller must never show a system prompt on its own.
      expect(gateway.requests, 0);
    });

    test('shows the prompt when the permission can still be had', () async {
      final gateway = GrantOnPromptGateway();
      final container = _containerWith(gateway);
      await container.read(locationPermissionControllerProvider.future);

      final status = await container
          .read(locationPermissionControllerProvider.notifier)
          .requestWhenInUse();

      expect(status, LocationPermissionStatus.granted);
      expect(gateway.requests, 1);
      expect(
        container.read(locationPermissionControllerProvider).value,
        LocationPermissionStatus.granted,
      );
    });

    test('never prompts again once the rider refused for good', () async {
      final gateway = FakeLocationPermissionGateway(
        status: LocationPermissionStatus.deniedForever,
      );
      final container = _containerWith(gateway);
      await container.read(locationPermissionControllerProvider.future);

      final status = await container
          .read(locationPermissionControllerProvider.notifier)
          .requestWhenInUse();

      // Only the app settings can undo this; a prompt would do nothing.
      expect(status, LocationPermissionStatus.deniedForever);
      expect(gateway.requests, 0);
    });

    test('does not prompt for a permission that is already held', () async {
      final gateway = FakeLocationPermissionGateway();
      final container = _containerWith(gateway);
      await container.read(locationPermissionControllerProvider.future);

      expect(
        await container
            .read(locationPermissionControllerProvider.notifier)
            .requestWhenInUse(),
        LocationPermissionStatus.granted,
      );
      expect(gateway.requests, 0);
    });

    test('does not prompt while the location service is off', () async {
      final gateway = FakeLocationPermissionGateway(
        status: LocationPermissionStatus.serviceDisabled,
      );
      final container = _containerWith(gateway);
      await container.read(locationPermissionControllerProvider.future);

      expect(
        await container
            .read(locationPermissionControllerProvider.notifier)
            .requestWhenInUse(),
        LocationPermissionStatus.serviceDisabled,
      );
      expect(gateway.requests, 0);
    });

    test('refresh picks up a permission granted in the settings', () async {
      final gateway = FakeLocationPermissionGateway(
        status: LocationPermissionStatus.deniedForever,
      );
      final container = _containerWith(gateway);
      final seen = <LocationPermissionStatus?>[];
      container.listen(
        locationPermissionControllerProvider,
        (_, next) => seen.add(next.value),
      );
      await container.read(locationPermissionControllerProvider.future);

      gateway.status = LocationPermissionStatus.granted;
      final status = await container
          .read(locationPermissionControllerProvider.notifier)
          .refresh();

      expect(status, LocationPermissionStatus.granted);
      expect(
        container.read(locationPermissionControllerProvider).value,
        LocationPermissionStatus.granted,
      );
      expect(seen, [
        LocationPermissionStatus.deniedForever,
        LocationPermissionStatus.granted,
      ]);
    });

    test('hands both settings requests to the gateway', () async {
      final gateway = FakeLocationPermissionGateway();
      final container = _containerWith(gateway);
      final controller = container.read(
        locationPermissionControllerProvider.notifier,
      );

      expect(await controller.openAppSettings(), isTrue);
      expect(gateway.openedAppSettings, isTrue);

      expect(await controller.openLocationSettings(), isTrue);
      expect(gateway.openedLocationSettings, isTrue);
    });
  });
}
