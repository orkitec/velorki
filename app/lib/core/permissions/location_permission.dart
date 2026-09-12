import 'package:geolocator/geolocator.dart' as geo;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'location_permission.g.dart';

/// What the app is allowed to do with the device location, collapsed into the
/// four cases the UI has to react to.
///
/// Only "when in use" is ever asked for. Background location is a separate
/// permission that belongs to ride recording (M3), not here.
enum LocationPermissionStatus {
  /// Not granted yet, but the system prompt can still be shown.
  denied,

  /// Refused for good; only the system settings can change it.
  deniedForever,

  /// Granted, at least while the app is in use.
  granted,

  /// Granted or not, the device's location service is switched off.
  serviceDisabled,
}

extension LocationPermissionStatusX on LocationPermissionStatus {
  /// Whether a position stream can be subscribed to.
  bool get isUsable => this == LocationPermissionStatus.granted;

  /// Whether asking again would show the system prompt rather than do nothing.
  bool get canAsk => this == LocationPermissionStatus.denied;
}

/// The platform calls behind [LocationPermissionController], so tests can run
/// the flow without a plugin.
abstract interface class LocationPermissionGateway {
  /// Current status, without showing any prompt.
  Future<LocationPermissionStatus> check();

  /// Shows the system prompt when that is still possible.
  Future<LocationPermissionStatus> request();

  /// Opens the app's own settings page.
  Future<bool> openAppSettings();

  /// Opens the system location settings page.
  Future<bool> openLocationSettings();
}

/// [LocationPermissionGateway] over geolocator.
class GeolocatorLocationPermissionGateway implements LocationPermissionGateway {
  const GeolocatorLocationPermissionGateway();

  @override
  Future<LocationPermissionStatus> check() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionStatus.serviceDisabled;
    }
    return _map(await geo.Geolocator.checkPermission());
  }

  @override
  Future<LocationPermissionStatus> request() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionStatus.serviceDisabled;
    }
    return _map(await geo.Geolocator.requestPermission());
  }

  @override
  Future<bool> openAppSettings() => geo.Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => geo.Geolocator.openLocationSettings();

  static LocationPermissionStatus _map(geo.LocationPermission permission) =>
      switch (permission) {
        geo.LocationPermission.always ||
        geo.LocationPermission.whileInUse => LocationPermissionStatus.granted,
        geo.LocationPermission.deniedForever =>
          LocationPermissionStatus.deniedForever,
        geo.LocationPermission.denied ||
        geo.LocationPermission.unableToDetermine =>
          LocationPermissionStatus.denied,
      };
}

@Riverpod(keepAlive: true)
LocationPermissionGateway locationPermissionGateway(Ref ref) =>
    const GeolocatorLocationPermissionGateway();

/// The current when-in-use location permission.
///
/// The rationale shown before the system prompt is the caller's job: see
/// `features/map/presentation/location_rationale_dialog.dart`. Store policy
/// asks for the explanation before the prompt, not after.
@Riverpod(keepAlive: true)
class LocationPermissionController extends _$LocationPermissionController {
  @override
  Future<LocationPermissionStatus> build() =>
      ref.watch(locationPermissionGatewayProvider).check();

  /// Re-reads the status, e.g. after coming back from the system settings.
  Future<LocationPermissionStatus> refresh() async {
    final status = await ref.read(locationPermissionGatewayProvider).check();
    state = AsyncData(status);
    return status;
  }

  /// Asks for when-in-use access, showing the system prompt only when that
  /// can still do something.
  Future<LocationPermissionStatus> requestWhenInUse() async {
    final gateway = ref.read(locationPermissionGatewayProvider);
    var status = await gateway.check();
    if (status == LocationPermissionStatus.denied) {
      status = await gateway.request();
    }
    state = AsyncData(status);
    return status;
  }

  /// Opens the app settings so a permanent denial can be undone.
  Future<bool> openAppSettings() =>
      ref.read(locationPermissionGatewayProvider).openAppSettings();

  /// Opens the system location settings so the service can be switched on.
  Future<bool> openLocationSettings() =>
      ref.read(locationPermissionGatewayProvider).openLocationSettings();
}
