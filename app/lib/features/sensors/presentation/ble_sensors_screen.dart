import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../recording/presentation/recording_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/ble_sources_controller.dart';
import '../application/sensor_hub.dart';
import '../data/ble_gateway.dart';
import '../data/ble_sensor_source.dart';
import '../data/paired_sensors.dart';
import '../data/sensor_settings.dart';
import '../domain/ble_profiles.dart';
import '../domain/sensor_reading.dart';
import '../domain/sensor_snapshot.dart';

final Logger _log = Logger('velorki.sensors.ble');

/// How long a scan runs before it gives up.
///
/// Long enough for a strap that only advertises every few seconds, short
/// enough that a radio left scanning is not what drains the battery of a rider
/// who walked away from this screen.
const Duration bleScanDuration = Duration(seconds: 15);

/// Settings → Sensors → Bluetooth sensors: find a strap, a cadence sensor or a
/// power meter, pair it, and watch what it reports.
///
/// This screen is the only place in the app that can raise the Bluetooth
/// permission prompt, and only the Scan button does it — a rider who never
/// comes here is never asked, and nothing is scanned for or connected to in
/// the meantime. While it is open the paired devices are connected so their
/// readings can be shown; leaving it disconnects them again unless a ride is
/// recording.
class BleSensorsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BleSensorsScreen({super.key});

  @override
  ConsumerState<BleSensorsScreen> createState() => _BleSensorsScreenState();
}

class _BleSensorsScreenState extends ConsumerState<BleSensorsScreen> {
  /// What the scan has heard so far, newest reading of each device.
  final Map<String, BleAdvertisement> _found = <String, BleAdvertisement>{};

  StreamSubscription<BleAdvertisement>? _scan;
  Timer? _scanTimer;
  bool _scanning = false;

  /// The device being connected to for its services, while a tap is pairing.
  String? _pairing;

  /// The claim this screen holds, kept rather than looked up again: `ref` is
  /// not safe to read from `dispose`, and the claim has to be given back
  /// there.
  late final BleLiveClaims _live;

  @override
  void initState() {
    super.initState();
    _live = ref.read(bleLiveProvider)..acquire();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(_scan?.cancel());
    _live.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final paired = ref.watch(pairedSensorsProvider);
    final pairedIds = <String>{for (final sensor in paired) sensor.id};
    final found = <BleAdvertisement>[
      for (final advertisement in _found.values)
        if (!pairedIds.contains(advertisement.id)) advertisement,
    ]..sort((a, b) => b.rssi.compareTo(a.rssi));
    final hasSpeed = paired.any(
      (sensor) => sensor.kinds.contains(SensorKind.speed),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSensorsBluetooth)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _scanning ? null : () => unawaited(_startScan()),
                  icon: _scanning
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(_scanning ? l10n.bleScanning : l10n.bleScan),
                ),
                // Said before the sheet appears rather than after it was
                // refused: the rider taps Scan knowing what it will ask for.
                if (defaultTargetPlatform == TargetPlatform.iOS)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.bleIosNote,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          if (_scanning || found.isNotEmpty) ...[
            const _Caption(_Section.found),
            if (found.isEmpty)
              _Hint(l10n.bleNothingFound)
            else
              for (final advertisement in found)
                _FoundTile(
                  advertisement: advertisement,
                  busy: _pairing == advertisement.id,
                  onTap: () => unawaited(_pair(advertisement)),
                ),
          ],
          const _Caption(_Section.paired),
          if (paired.isEmpty)
            _Hint(l10n.bleNothingPaired)
          else
            for (final sensor in paired)
              _PairedTile(
                sensor: sensor,
                onForget: () => unawaited(
                  ref.read(pairedSensorsProvider.notifier).forget(sensor.id),
                ),
              ),
          if (hasSpeed) const _WheelCircumferenceField(),
        ],
      ),
    );
  }

  /// Asks for what a scan needs and then listens for [bleScanDuration].
  Future<void> _startScan() async {
    final gateway = ref.read(bleGatewayProvider);
    if (gateway == null || _scanning) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    // The only prompt this feature ever raises, and only from here.
    if (!await gateway.ensurePermissions()) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.blePermissionDenied)));
      return;
    }
    if (!await gateway.isOn()) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.bleAdapterOff)));
      return;
    }
    if (!mounted) return;

    setState(() {
      _scanning = true;
      _found.clear();
    });
    _scan = gateway
        .scan(serviceUuids: bleSensorServiceUuids)
        .listen(
          (advertisement) {
            if (!mounted) return;
            setState(() => _found[advertisement.id] = advertisement);
          },
          onError: (Object error, StackTrace stackTrace) {
            _log.warning('ble scan failed', error, stackTrace);
            _stopScan();
          },
        );
    _scanTimer = Timer(bleScanDuration, _stopScan);
  }

  void _stopScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    unawaited(_scan?.cancel());
    _scan = null;
    if (!mounted || !_scanning) return;
    setState(() => _scanning = false);
  }

  /// Pairs [advertisement]: one connection, to ask the device what it actually
  /// has, and then the kinds are stored and the connection given back. What it
  /// advertised stands in when it could not be reached at all.
  Future<void> _pair(BleAdvertisement advertisement) async {
    final gateway = ref.read(bleGatewayProvider);
    if (gateway == null || _pairing != null) return;
    setState(() => _pairing = advertisement.id);
    var kinds = bleKindsForServices(advertisement.serviceUuids);
    try {
      final connection = await gateway.connect(advertisement.id);
      try {
        final services = await connection.discoverServices();
        final discovered = bleKindsForServices(services);
        if (discovered.isNotEmpty) kinds = discovered;
      } finally {
        await connection.disconnect();
      }
    } on Object catch (error, stackTrace) {
      _log.info('pairing ${advertisement.id} found nothing', error, stackTrace);
    }
    await ref
        .read(pairedSensorsProvider.notifier)
        .pair(
          PairedSensor(
            id: advertisement.id,
            name: advertisement.name,
            kinds: kinds,
          ),
        );
    if (!mounted) return;
    setState(() {
      _pairing = null;
      _found.remove(advertisement.id);
    });
  }
}

enum _Section { found, paired }

class _Caption extends StatelessWidget {
  const _Caption(this.section);

  final _Section section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: SectionCaption(switch (section) {
        _Section.found => l10n.bleFound,
        _Section.paired => l10n.blePaired,
      }),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

/// A device a scan heard, with how loudly it was heard.
class _FoundTile extends StatelessWidget {
  const _FoundTile({
    required this.advertisement,
    required this.busy,
    required this.onTap,
  });

  final BleAdvertisement advertisement;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kinds = bleKindsForServices(advertisement.serviceUuids);
    return ListTile(
      leading: _KindIcons(kinds),
      title: Text(
        advertisement.name.isEmpty ? l10n.bleUnnamedSensor : advertisement.name,
      ),
      subtitle: Text(l10n.bleSignal(advertisement.rssi)),
      trailing: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
      onTap: busy ? null : onTap,
    );
  }
}

/// A paired device: where its link stands, and what it is saying right now.
class _PairedTile extends ConsumerWidget {
  const _PairedTile({required this.sensor, required this.onForget});

  final PairedSensor sensor;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status =
        ref.watch(bleSourcesProvider)[sensor.id] ?? BleLinkStatus.off;
    final snapshot = ref.watch(sensorHubProvider).readingsAt(DateTime.now());
    final live = snapshot.liveSourceIds.contains(bleSensorSourceId(sensor.id));
    final readings = live
        ? _readings(l10n, ref.watch(unitSystemProvider), snapshot)
        : '';
    return ListTile(
      leading: _KindIcons(sensor.kinds),
      title: Text(sensor.name.isEmpty ? l10n.bleUnnamedSensor : sensor.name),
      subtitle: Text(readings.isEmpty ? _statusText(l10n, status) : readings),
      trailing: PopupMenuButton<void>(
        itemBuilder: (context) => <PopupMenuEntry<void>>[
          PopupMenuItem<void>(onTap: onForget, child: Text(l10n.bleForget)),
        ],
      ),
    );
  }

  String _statusText(AppLocalizations l10n, BleLinkStatus status) =>
      switch (status) {
        BleLinkStatus.connected => l10n.bleConnected,
        BleLinkStatus.connecting => l10n.bleConnecting,
        BleLinkStatus.off => l10n.bleNotConnected,
      };

  /// What this device's kinds are reading, out of the hub.
  ///
  /// The hub has already resolved every kind across every source, so with a
  /// watch reporting as well the heart rate shown here is the watch's — which
  /// is the number the rider is being given anyway, and the honest one.
  String _readings(
    AppLocalizations l10n,
    units.UnitSystem system,
    SensorSnapshot snapshot,
  ) => <String>[
    for (final kind in SensorKind.values)
      if (sensor.kinds.contains(kind))
        switch (kind) {
          SensorKind.heartRate when snapshot.heartRateBpm != null =>
            formatHeartRate(l10n, snapshot.heartRateBpm),
          SensorKind.cadence when snapshot.cadenceRpm != null => formatCadence(
            l10n,
            snapshot.cadenceRpm,
          ),
          SensorKind.speed when snapshot.speedMps != null => formatSpeed(
            l10n,
            system,
            snapshot.speedMps!,
          ),
          SensorKind.power when snapshot.powerW != null => formatPower(
            l10n,
            snapshot.powerW,
          ),
          _ => '',
        },
  ].where((reading) => reading.isNotEmpty).join(' · ');
}

/// One small icon per kind, which is how a strap is told from a crank at a
/// glance.
class _KindIcons extends StatelessWidget {
  const _KindIcons(this.kinds);

  final Set<SensorKind> kinds;

  static const Map<SensorKind, IconData> _icons = <SensorKind, IconData>{
    SensorKind.heartRate: Icons.favorite_outline,
    SensorKind.cadence: Icons.autorenew,
    SensorKind.speed: Icons.speed_outlined,
    SensorKind.power: Icons.bolt_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final kind in SensorKind.values)
            if (kinds.contains(kind))
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(_icons[kind], size: 18, color: colour),
              ),
        ],
      ),
    );
  }
}

/// The wheel a speed sensor is on.
///
/// Only shown once a paired device reports speed: a strap and a power meter
/// need no wheel, and a number nobody's sensor uses is a question nobody
/// should be asked.
class _WheelCircumferenceField extends ConsumerStatefulWidget {
  const _WheelCircumferenceField();

  @override
  ConsumerState<_WheelCircumferenceField> createState() =>
      _WheelCircumferenceFieldState();
}

class _WheelCircumferenceFieldState
    extends ConsumerState<_WheelCircumferenceField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${ref.read(sensorSettingsProvider).wheelCircumferenceMm}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: InputDecoration(
          labelText: l10n.bleWheelCircumference,
          helperText: l10n.bleWheelCircumferenceHint,
          suffixText: l10n.bleWheelCircumferenceUnit,
          border: const OutlineInputBorder(),
        ),
        // Saved as it is typed, but only once the number could be a wheel: a
        // half-typed "21" is not a correction to 21 mm.
        onChanged: (value) {
          final millimetres = int.tryParse(value);
          if (millimetres == null) return;
          if (millimetres < minWheelCircumferenceMm ||
              millimetres > maxWheelCircumferenceMm) {
            return;
          }
          unawaited(
            ref
                .read(sensorSettingsProvider.notifier)
                .setWheelCircumferenceMm(millimetres),
          );
        },
      ),
    );
  }
}
