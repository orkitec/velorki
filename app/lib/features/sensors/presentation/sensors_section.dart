import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/ble_gateway.dart';
import '../data/health_gateway.dart';
import '../data/paired_sensors.dart';
import '../data/sensor_settings.dart';
import '../data/watch_gateway.dart';
import '../../recording/data/recording_gateways.dart';
import 'ble_sensors_screen.dart';

/// Settings → Sensors: the switch that connects Velorki to the phone's health
/// store, whether finished rides go back into it, and the one that lets the
/// rider's watch into the ride.
///
/// Nothing in this feature runs until a switch is on. Turning Health on is the
/// only thing in the app that can raise the health permission prompt, and a
/// rider who never comes here is never asked. The watch switch raises no
/// prompt at all: the watch app asks the OS on the *watch* for its heart rate,
/// the first time the rider opens it. The Bluetooth row raises none either —
/// it only opens the screen where the Scan button does.
class SensorsSection extends ConsumerWidget {
  /// Creates the section.
  const SensorsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gateway = ref.watch(healthGatewayProvider);
    if (gateway == null) return const SizedBox.shrink();
    final settings = ref.watch(sensorSettingsProvider);
    final controller = ref.read(sensorSettingsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          value: settings.health,
          title: Text(
            defaultTargetPlatform == TargetPlatform.android
                ? l10n.settingsSensorsHealthConnect
                : l10n.settingsSensorsAppleHealth,
          ),
          subtitle: Text(l10n.settingsSensorsHealthHint),
          onChanged: (value) => unawaited(
            _setHealth(
              value,
              gateway: gateway,
              controller: controller,
              settings: settings,
              messenger: messenger,
              l10n: l10n,
            ),
          ),
        ),
        // Writing is the half that leaves the phone's own store, so it can be
        // switched off on its own; it has nothing to write while there is no
        // connection at all.
        SwitchListTile(
          value: settings.healthWrite,
          title: Text(l10n.settingsSensorsHealthWrite),
          onChanged: settings.health
              ? (value) => unawaited(controller.setHealthWrite(value))
              : null,
        ),
        // Only on a phone that has a watch paired to it: everywhere else the
        // switch could do nothing at all, so it is not offered.
        if (ref.watch(watchPairedProvider).value ?? false) ...[
          SwitchListTile(
            value: settings.watch,
            title: Text(l10n.settingsSensorsAppleWatch),
            subtitle: Text(l10n.settingsSensorsWatchHint),
            onChanged: (value) => unawaited(
              _setWatch(
                value,
                controller: controller,
                notifications: ref.read(notificationPermissionProvider),
              ),
            ),
          ),
          // The trade for rides with many stops: the sensor rests at every
          // pause, and the watch app is woken again when the ride goes on.
          SwitchListTile(
            value: settings.watchRest,
            title: Text(l10n.settingsSensorsWatchRest),
            subtitle: Text(l10n.settingsSensorsWatchRestHint),
            onChanged: settings.watch
                ? (value) => unawaited(controller.setWatchRest(value))
                : null,
          ),
        ],
        // Only where there is a radio to use. The row itself connects to
        // nothing; the screen behind it is where a rider goes looking.
        if (ref.watch(bleGatewayProvider) != null) const _BluetoothEntry(),
      ],
    );
  }

  /// Turning the watch on also asks to post notifications, once: a ride
  /// started from the wrist with the phone app closed is announced on the
  /// phone so a tap brings the app up. A refusal only costs that
  /// announcement; the switch goes on either way.
  Future<void> _setWatch(
    bool value, {
    required SensorSettingsController controller,
    required NotificationPermissionGateway notifications,
  }) async {
    await controller.setWatch(value);
    if (value && !await notifications.isGranted()) {
      await notifications.request();
    }
  }

  /// Turning the switch on asks the OS first: the setting only follows once
  /// access was actually granted, so a refused prompt leaves the switch off
  /// rather than promising a heart rate that will never arrive.
  Future<void> _setHealth(
    bool value, {
    required HealthGateway gateway,
    required SensorSettingsController controller,
    required SensorSettings settings,
    required ScaffoldMessengerState messenger,
    required AppLocalizations l10n,
  }) async {
    if (!value) return controller.setHealth(false);
    final granted = await gateway.requestAuthorization(
      write: settings.healthWrite,
    );
    if (!granted) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsSensorsHealthDenied)),
      );
      return;
    }
    await controller.setHealth(true);
  }
}

/// The row into the Bluetooth sensors screen, saying how many devices are
/// paired.
class _BluetoothEntry extends ConsumerWidget {
  const _BluetoothEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final paired = ref.watch(pairedSensorsProvider);
    return ListTile(
      title: Text(l10n.settingsSensorsBluetooth),
      subtitle: Text(
        paired.isEmpty
            ? l10n.settingsSensorsBluetoothHint
            : l10n.settingsSensorsBluetoothPaired(paired.length),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const BleSensorsScreen())),
    );
  }
}
