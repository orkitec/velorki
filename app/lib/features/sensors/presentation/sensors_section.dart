import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/health_gateway.dart';
import '../data/sensor_settings.dart';

/// Settings → Sensors: the one switch that connects Velorki to the phone's
/// health store, and whether finished rides go back into it.
///
/// Nothing in this feature runs until the first switch is on. Turning it on is
/// the only thing in the app that can raise the health permission prompt, and
/// a rider who never comes here is never asked.
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
      ],
    );
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
