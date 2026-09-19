import 'dart:async';

import '../data/ble_gateway.dart';
import '../domain/ble_profiles.dart';

/// One device a [FakeBleGateway] pretends is in the room.
class FakeBleDevice {
  /// Creates a device offering [serviceUuids].
  FakeBleDevice({
    required this.id,
    required this.name,
    required this.serviceUuids,
    this.rssi = -55,
  });

  /// A heart rate strap.
  factory FakeBleDevice.strap({
    String id = 'strap-1',
    String name = 'Chest Strap',
    int rssi = -55,
  }) => FakeBleDevice(
    id: id,
    name: name,
    serviceUuids: <String>{heartRateServiceUuid},
    rssi: rssi,
  );

  /// A speed and cadence sensor.
  factory FakeBleDevice.cadence({
    String id = 'cadence-1',
    String name = 'Speed & Cadence',
    int rssi = -60,
  }) => FakeBleDevice(
    id: id,
    name: name,
    serviceUuids: <String>{cyclingSpeedCadenceServiceUuid},
    rssi: rssi,
  );

  /// A power meter, which counts its crank as well.
  factory FakeBleDevice.power({
    String id = 'power-1',
    String name = 'Power Meter',
    int rssi = -65,
  }) => FakeBleDevice(
    id: id,
    name: name,
    serviceUuids: <String>{cyclingPowerServiceUuid},
    rssi: rssi,
  );

  /// What the platform calls it.
  final String id;

  /// What it calls itself.
  String name;

  /// The services it advertises and exposes.
  final Set<String> serviceUuids;

  /// How loud it is, in dBm.
  int rssi;
}

/// A [BleGateway] with scripted devices and notifications that writes down
/// what it was asked to do.
///
/// Lives in `lib/` rather than `test/` so the widget tests and the integration
/// tests can both override `bleGatewayProvider` with it — the same reason
/// `FakeHealthGateway` and `FakeWatchGateway` do.
///
/// The notification helpers build real packets in the layout the profiles
/// prescribe, and keep the cumulative counters a sensor keeps, so a test that
/// asks for 85 rpm exercises the parsers all the way to 85 rpm rather than
/// handing a number straight to the source.
class FakeBleGateway implements BleGateway {
  /// Creates a fake. A supported, switched-on radio that grants what it is
  /// asked for, because that is what most tests are about.
  FakeBleGateway({
    this.supported = true,
    this.on = true,
    this.permitted = true,
    this.connectable = true,
    List<FakeBleDevice> devices = const <FakeBleDevice>[],
  }) : devices = <FakeBleDevice>[...devices];

  /// What [isSupported] answers.
  bool supported;

  /// What [isOn] answers — `false` is a radio the rider has switched off.
  bool on;

  /// What [ensurePermissions] answers — `false` is an OS that refused.
  bool permitted;

  /// Whether [connect] succeeds at all. `false` is a device out of range,
  /// which is what the source's backoff is for.
  bool connectable;

  /// The devices in the room; a test may add to this at any time.
  final List<FakeBleDevice> devices;

  /// How often permissions were asked for.
  int permissionRequests = 0;

  /// Every set of services a scan filtered on, in order.
  final List<Set<String>> scans = <Set<String>>[];

  /// Every device id [connect] was called with, in order, including the
  /// retries after a drop.
  final List<String> connects = <String>[];

  final Map<String, StreamController<List<int>>> _channels =
      <String, StreamController<List<int>>>{};
  final Map<String, _FakeBleConnection> _connections =
      <String, _FakeBleConnection>{};
  final Map<String, _Counters> _counters = <String, _Counters>{};

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isOn() async => on;

  @override
  Future<bool> ensurePermissions() async {
    permissionRequests++;
    return permitted;
  }

  @override
  Stream<BleAdvertisement> scan({required Set<String> serviceUuids}) {
    scans.add(serviceUuids);
    final controller = StreamController<BleAdvertisement>();
    controller.onListen = () {
      for (final device in devices) {
        if (controller.isClosed) return;
        if (!device.serviceUuids.any(serviceUuids.contains)) continue;
        controller.add(
          BleAdvertisement(
            id: device.id,
            name: device.name,
            serviceUuids: device.serviceUuids,
            rssi: device.rssi,
          ),
        );
      }
    };
    return controller.stream;
  }

  @override
  Future<BleConnection> connect(String id) async {
    connects.add(id);
    final device = deviceOf(id);
    if (!connectable || device == null) {
      throw StateError('no device $id in range');
    }
    final connection = _FakeBleConnection(this, device);
    _connections[id] = connection;
    return connection;
  }

  /// The scripted device with [id], or `null` when there is none.
  FakeBleDevice? deviceOf(String id) {
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  /// Whether a connection to [id] is open right now.
  bool isConnected(String id) => _connections[id]?.isOpen ?? false;

  /// Drops the link to [id], as a strap carried out of range does. The source
  /// is expected to come back for it.
  void drop(String id) => _connections[id]?.close();

  /// Pushes one raw notification from [deviceId].
  void notify(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    List<int> data,
  ) {
    final channel = _channels['$deviceId|$serviceUuid|$characteristicUuid'];
    if (channel == null || channel.isClosed) return;
    channel.add(data);
  }

  /// Plays one heart rate measurement.
  void beat(String deviceId, int bpm) => notify(
    deviceId,
    heartRateServiceUuid,
    heartRateMeasurementUuid,
    bpm <= 0xFF ? <int>[0x00, bpm] : <int>[0x01, bpm & 0xFF, (bpm >> 8) & 0xFF],
  );

  /// Plays one CSC measurement with crank data only, advancing the counters by
  /// exactly one revolution at [rpm].
  void crank(String deviceId, double rpm) {
    final counters = _countersOf(deviceId);
    counters.crankRevolutions = (counters.crankRevolutions + 1) & 0xFFFF;
    counters.crankEventTime =
        (counters.crankEventTime + (60 / rpm * 1024).round()) & 0xFFFF;
    notify(deviceId, cyclingSpeedCadenceServiceUuid, cscMeasurementUuid, <int>[
      0x02,
      ..._le16(counters.crankRevolutions),
      ..._le16(counters.crankEventTime),
    ]);
  }

  /// Plays one CSC measurement with wheel data only, advancing the counters by
  /// exactly one revolution of a [circumferenceM] wheel at [speedMps].
  void wheel(
    String deviceId, {
    required double speedMps,
    double circumferenceM = defaultWheelCircumferenceMm / 1000,
  }) {
    final counters = _countersOf(deviceId);
    counters.wheelRevolutions = (counters.wheelRevolutions + 1) & 0xFFFFFFFF;
    counters.wheelEventTime =
        (counters.wheelEventTime + (circumferenceM / speedMps * 1024).round()) &
        0xFFFF;
    notify(deviceId, cyclingSpeedCadenceServiceUuid, cscMeasurementUuid, <int>[
      0x01,
      ..._le32(counters.wheelRevolutions),
      ..._le16(counters.wheelEventTime),
    ]);
  }

  /// Plays one Cycling Power measurement, with the crank counters when
  /// [cadenceRpm] is given.
  void watts(String deviceId, int powerW, {double? cadenceRpm}) {
    final power = <int>[..._le16(powerW & 0xFFFF)];
    if (cadenceRpm == null) {
      notify(
        deviceId,
        cyclingPowerServiceUuid,
        cyclingPowerMeasurementUuid,
        <int>[..._le16(0), ...power],
      );
      return;
    }
    final counters = _countersOf(deviceId);
    counters.crankRevolutions = (counters.crankRevolutions + 1) & 0xFFFF;
    counters.crankEventTime =
        (counters.crankEventTime + (60 / cadenceRpm * 1024).round()) & 0xFFFF;
    notify(
      deviceId,
      cyclingPowerServiceUuid,
      cyclingPowerMeasurementUuid,
      <int>[
        ..._le16(0x20),
        ...power,
        ..._le16(counters.crankRevolutions),
        ..._le16(counters.crankEventTime),
      ],
    );
  }

  /// Closes every channel. A test that made one calls this in a teardown.
  ///
  /// The closes are not awaited: a test that ran the fake inside `fakeAsync`
  /// leaves futures behind that only that zone can complete, and a teardown
  /// waiting for one of them would wait for ever.
  Future<void> dispose() async {
    for (final connection in _connections.values) {
      connection.close();
    }
    _connections.clear();
    for (final channel in _channels.values) {
      unawaited(channel.close());
    }
    _channels.clear();
  }

  StreamController<List<int>> _channel(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => _channels.putIfAbsent(
    '$deviceId|$serviceUuid|$characteristicUuid',
    StreamController<List<int>>.broadcast,
  );

  _Counters _countersOf(String deviceId) =>
      _counters.putIfAbsent(deviceId, _Counters.new);

  static List<int> _le16(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

  static List<int> _le32(int value) => <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];
}

/// The cumulative counters a scripted sensor keeps between notifications.
class _Counters {
  int wheelRevolutions = 0;
  int wheelEventTime = 0;
  int crankRevolutions = 0;
  int crankEventTime = 0;
}

class _FakeBleConnection implements BleConnection {
  _FakeBleConnection(this._gateway, this._device);

  final FakeBleGateway _gateway;
  final FakeBleDevice _device;

  final StreamController<BleConnectionState> _states =
      StreamController<BleConnectionState>.broadcast();

  bool isOpen = true;

  @override
  String get deviceId => _device.id;

  /// What the link does from here on. Nothing is replayed: a connection
  /// starts connected, which is what [BleGateway.connect] returning it means,
  /// and the only event there is to hear is the drop.
  @override
  Stream<BleConnectionState> get connectionState => _states.stream;

  @override
  Future<Set<String>> discoverServices() async => _device.serviceUuids;

  @override
  Stream<List<int>> notifications(
    String serviceUuid,
    String characteristicUuid,
  ) {
    if (!_device.serviceUuids.contains(serviceUuid)) {
      return const Stream<List<int>>.empty();
    }
    return _gateway
        ._channel(deviceId, serviceUuid, characteristicUuid)
        .stream
        .where((_) => isOpen);
  }

  @override
  Future<void> disconnect() async => close();

  /// Ends the link, telling whoever is listening.
  void close() {
    if (!isOpen) return;
    isOpen = false;
    if (!_states.isClosed) {
      _states.add(BleConnectionState.disconnected);
      unawaited(_states.close());
    }
  }
}
