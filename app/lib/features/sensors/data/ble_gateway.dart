import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:universal_ble/universal_ble.dart';

part 'ble_gateway.g.dart';

final Logger _log = Logger('velorki.sensors.ble');

/// One device seen during a scan.
///
/// Velorki's own vocabulary rather than the plugin's: the ids and the service
/// uuids are plain strings, and a uuid is always the shortest form the
/// Bluetooth registry gives it — `180d`, not the 128-bit spelling of the same
/// thing — so it compares equal to the constants in `ble_profiles.dart`.
@immutable
class BleAdvertisement {
  /// Creates an advertisement.
  const BleAdvertisement({
    required this.id,
    required this.name,
    required this.serviceUuids,
    required this.rssi,
  });

  /// What the platform calls this device. A MAC address on Android, an opaque
  /// per-app identifier on Apple; stable enough to reconnect to either way.
  final String id;

  /// What it calls itself, empty when it advertises no name.
  final String name;

  /// The services it says it has.
  final Set<String> serviceUuids;

  /// Signal strength in dBm, the negative number that tells the rider's own
  /// strap from the one in the next flat.
  final int rssi;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleAdvertisement &&
          other.id == id &&
          other.name == name &&
          setEquals(other.serviceUuids, serviceUuids) &&
          other.rssi == rssi;

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAllUnordered(serviceUuids), rssi);

  @override
  String toString() =>
      'BleAdvertisement($id "$name", $serviceUuids, $rssi dBm)';
}

/// Where a connection stands.
enum BleConnectionState {
  /// The link is being set up.
  connecting,

  /// The device is connected and its characteristics can be read.
  connected,

  /// It is not connected, whether it was dropped or never reached.
  disconnected,
}

/// One connected device.
///
/// Handed out by [BleGateway.connect] and good for one connection: a link that
/// drops is a new [BleConnection] once it comes back, which is what the source
/// does on its reconnect.
abstract interface class BleConnection {
  /// The device this is a link to, as [BleAdvertisement.id].
  String get deviceId;

  /// Where the link stands, as it changes.
  Stream<BleConnectionState> get connectionState;

  /// The services the device actually exposes, as short uuids.
  ///
  /// What it advertises and what it has are not the same list: a strap that
  /// advertises only the heart rate service may still carry a battery service,
  /// and a head unit finds out by asking.
  Future<Set<String>> discoverServices();

  /// Everything one characteristic notifies, as it notifies it.
  ///
  /// An empty stream when the device does not have that characteristic at all,
  /// so a caller that asked for one kind too many simply hears nothing.
  Stream<List<int>> notifications(
    String serviceUuid,
    String characteristicUuid,
  );

  /// Drops the link. Safe to call twice.
  Future<void> disconnect();
}

/// The phone's Bluetooth Low Energy radio, as the little of it Velorki uses.
///
/// Everything `universal_ble` offers is behind this one interface, so the tests
/// never touch the plugin and nothing above it learns the plugin's vocabulary.
/// Nothing here runs by itself: the first call that can raise an OS prompt is
/// [ensurePermissions], and the only thing that makes it is the Scan button on
/// the Bluetooth sensors screen.
abstract interface class BleGateway {
  /// Whether this device has a Bluetooth Low Energy radio at all.
  Future<bool> isSupported();

  /// Whether the radio is switched on right now.
  Future<bool> isOn();

  /// Asks the OS for what a scan needs, showing its permission sheet.
  ///
  /// Returns whether scanning may go ahead. On iOS that sheet is CoreBluetooth
  /// asking for Bluetooth itself; on Android it is the scan and connect
  /// permissions, and the location permission as well on the versions that
  /// scanned on it.
  Future<bool> ensurePermissions();

  /// Advertisements from devices offering any of [serviceUuids], as they are
  /// heard. The scan runs for as long as the stream is listened to.
  Stream<BleAdvertisement> scan({required Set<String> serviceUuids});

  /// Connects to the device with [id].
  Future<BleConnection> connect(String id);
}

/// Whether [platform] has a Bluetooth radio Velorki can talk to.
///
/// The phones, and nothing else: the desktop builds exist for the planner, and
/// a scan button there would only ever find nothing.
bool bleSupportedOn(TargetPlatform platform) =>
    platform == TargetPlatform.iOS || platform == TargetPlatform.android;

/// [BleGateway] over the `universal_ble` package.
///
/// Every call is wrapped: a radio that was switched off mid-ride, a plugin
/// that is not there, a device that walked away — all of them answer "no"
/// instead of throwing into a recording.
class PluginBleGateway implements BleGateway {
  /// Creates a gateway. [platform] is only injected by this package's tests.
  PluginBleGateway({TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform;

  final TargetPlatform _platform;

  @override
  Future<bool> isSupported() async {
    if (!bleSupportedOn(_platform)) return false;
    return _guard('isSupported', false, () async {
      final state = await UniversalBle.getBluetoothAvailabilityState();
      return state != AvailabilityState.unsupported;
    });
  }

  @override
  Future<bool> isOn() => _guard('isOn', false, () async {
    final state = await UniversalBle.getBluetoothAvailabilityState();
    return state == AvailabilityState.poweredOn;
  });

  @override
  Future<bool> ensurePermissions() async {
    if (!bleSupportedOn(_platform)) return false;
    return _guard('ensurePermissions', false, () async {
      if (await UniversalBle.hasPermissions()) return true;
      // The plugin knows which permissions this Android version actually has —
      // the scan and connect pair from Android 12, the location permission
      // below it — which is knowledge Dart has no other way of getting. Fine
      // location is not asked for above that, because the scan is declared
      // neverForLocation and Velorki does not use a beacon to place anyone.
      // On iOS this is CoreBluetooth's own sheet. A refusal throws, and the
      // guard turns it into the "no" the Scan button shows.
      await UniversalBle.requestPermissions();
      return UniversalBle.hasPermissions();
    });
  }

  @override
  Stream<BleAdvertisement> scan({required Set<String> serviceUuids}) {
    final controller = StreamController<BleAdvertisement>();
    StreamSubscription<BleDevice>? results;

    Future<void> stop() async {
      await results?.cancel();
      results = null;
      await _guard('stopScan', null, UniversalBle.stopScan);
    }

    controller
      ..onListen = () async {
        // Subscribed before the scan starts, so nothing heard in the first
        // moments is missed.
        results = UniversalBle.scanStream.listen(
          (device) {
            if (controller.isClosed) return;
            controller.add(_advertisement(device));
          },
          onError: (Object error, StackTrace stackTrace) =>
              _log.warning('ble scan failed', error, stackTrace),
        );
        try {
          await UniversalBle.startScan(
            scanFilter: ScanFilter(
              withServices: <String>[
                for (final uuid in serviceUuids) BleUuidParser.string(uuid),
              ],
            ),
          );
        } on Object catch (error, stackTrace) {
          _log.warning('ble scan could not start', error, stackTrace);
          if (!controller.isClosed) controller.addError(error, stackTrace);
        }
      }
      ..onCancel = stop;
    return controller.stream;
  }

  @override
  Future<BleConnection> connect(String id) async {
    await UniversalBle.connect(id);
    return _PluginBleConnection(id);
  }

  static BleAdvertisement _advertisement(BleDevice device) => BleAdvertisement(
    id: device.deviceId,
    name: device.name ?? '',
    serviceUuids: <String>{
      for (final uuid in device.services) shortBleUuid(uuid),
    },
    // A platform that does not report a strength is treated as the weakest
    // there is, so a device that says nothing about itself sorts last rather
    // than first.
    rssi: device.rssi ?? -127,
  );
}

/// One link to one device, over `universal_ble`.
///
/// The plugin is a set of static calls keyed by device id rather than an
/// object, so this is the object: it holds the id, what the device was found
/// to have, and the subscriptions that have to be given back.
class _PluginBleConnection implements BleConnection {
  _PluginBleConnection(this.deviceId);

  @override
  final String deviceId;

  /// What [discoverServices] found, short uuid to its characteristics.
  Map<String, Set<String>> _services = const <String, Set<String>>{};

  /// The characteristics this connection subscribed to, so they can be
  /// unsubscribed from when it ends.
  final List<({String service, String characteristic})> _subscribed =
      <({String service, String characteristic})>[];

  bool _closed = false;

  @override
  Stream<BleConnectionState> get connectionState =>
      UniversalBle.connectionStream(deviceId).map(
        (connected) => connected
            ? BleConnectionState.connected
            : BleConnectionState.disconnected,
      );

  @override
  Future<Set<String>> discoverServices() async {
    final services = await UniversalBle.discoverServices(deviceId);
    _services = <String, Set<String>>{
      for (final service in services)
        shortBleUuid(service.uuid): <String>{
          for (final characteristic in service.characteristics)
            shortBleUuid(characteristic.uuid),
        },
    };
    return _services.keys.toSet();
  }

  @override
  Stream<List<int>> notifications(
    String serviceUuid,
    String characteristicUuid,
  ) async* {
    if (!(_services[serviceUuid]?.contains(characteristicUuid) ?? false)) {
      _log.info('$deviceId has no $serviceUuid/$characteristicUuid');
      return;
    }
    final service = BleUuidParser.string(serviceUuid);
    final characteristic = BleUuidParser.string(characteristicUuid);
    await UniversalBle.subscribeNotifications(
      deviceId,
      service,
      characteristic,
    );
    if (_closed) return;
    _subscribed.add((service: service, characteristic: characteristic));
    yield* UniversalBle.characteristicValueStream(deviceId, characteristic);
  }

  @override
  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    // Unsubscribing before the link goes is what leaves the sensor able to
    // sleep; a device that is already gone refuses, which is no news here.
    for (final subscription in _subscribed) {
      await _guard(
        'unsubscribe',
        null,
        () => UniversalBle.unsubscribe(
          deviceId,
          subscription.service,
          subscription.characteristic,
        ),
      );
    }
    _subscribed.clear();
    await _guard('disconnect', null, () => UniversalBle.disconnect(deviceId));
  }
}

/// A 128-bit uuid from the plugin in the short form Velorki speaks.
///
/// Everything in the Bluetooth registry is a 16-bit number inside one fixed
/// base uuid, so `0000180d-0000-1000-8000-00805f9b34fb` is `180d` and says the
/// same thing. A uuid outside that base belongs to a manufacturer and is kept
/// whole.
String shortBleUuid(String uuid) {
  final full = uuid.toLowerCase();
  if (full.length != 36) return full;
  if (!full.startsWith('0000')) return full;
  if (!full.endsWith('-0000-1000-8000-00805f9b34fb')) return full;
  return full.substring(4, 8);
}

Future<T> _guard<T>(String what, T fallback, Future<T> Function() body) async {
  try {
    return await body();
  } on Object catch (error, stackTrace) {
    _log.warning('ble $what failed', error, stackTrace);
    return fallback;
  }
}

/// The Bluetooth radio of this platform, or `null` where there is none.
///
/// Constructing it asks the OS for nothing and switches nothing on; the
/// gateway only reaches the plugin once something calls it, and the only
/// things that call it are the Bluetooth sensors screen and the sources behind
/// a paired device.
@Riverpod(keepAlive: true)
BleGateway? bleGateway(Ref ref) =>
    bleSupportedOn(defaultTargetPlatform) ? PluginBleGateway() : null;
