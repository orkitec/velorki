import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../app/platform_features.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../features/assistant/presentation/ai_settings_section.dart';
import '../../../features/integrations/common/data/connected_accounts_repository.dart';
import '../../../features/integrations/common/domain/connected_account.dart';
import '../../../features/integrations/presentation/connections_section.dart';
import '../../../features/integrations/presentation/integration_labels.dart';
import '../../../features/routing_tiles/data/routing_preference_controller.dart';
import '../../../features/routing_tiles/domain/routing_preference.dart';
import '../../../features/search/presentation/search_settings_screen.dart';
import '../../../features/sensors/data/health_gateway.dart';
import '../../../features/sensors/presentation/sensors_section.dart';
import '../../../features/offline/presentation/offline_entry.dart';
import '../../../features/subscription/presentation/plus_settings_section.dart';
import '../../../features/sync/application/cloud_sync_controller.dart';
import '../../../features/sync/presentation/cloud_sync_section.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../shared/presentation/wide_panel.dart';
import '../data/appearance_controller.dart';
import '../data/package_info_provider.dart';
import '../data/units.dart';
import 'about_section.dart';
import 'appearance_section.dart';
import 'language_section.dart';
import 'navigation_section.dart';
import 'recording_section.dart';
import 'rider_section.dart';
import 'units_section.dart';

/// One page of the settings, opened from a row of the overview.
enum SettingsTopic {
  /// Which cloud the library syncs with.
  sync,

  /// Velorki Plus: its state, Manage and Restore.
  plus,

  /// The partner services.
  connections,

  /// Turn directions, voice and re-routing.
  navigation,

  /// What a ride records and shows.
  recording,

  /// The rider and the bike.
  rider,

  /// The health store.
  sensors,

  /// Theme, map look, units and language.
  appearance,

  /// The AI assistant.
  assistant,

  /// Offline areas, search, routing and the server URLs.
  mapsData,

  /// Version, attribution, licences and the legal links.
  about,
}

/// Whether [topic] has anything to show here: a row disappears where its
/// section would.
bool _offered(SettingsTopic topic, PlatformFeatures features, WidgetRef ref) =>
    switch (topic) {
      // Only where there is a service to sync with (iCloud: iOS 17 and
      // later); hidden everywhere else.
      SettingsTopic.sync => ref.watch(offeredSyncServicesProvider).isNotEmpty,
      SettingsTopic.connections => features.accountConnections,
      // Where nothing records, nothing navigates either.
      SettingsTopic.navigation || SettingsTopic.recording => features.recording,
      // Hidden where there is no health store to talk to, rather than shown
      // as a switch that cannot do anything.
      SettingsTopic.sensors =>
        features.recording && ref.watch(healthGatewayProvider) != null,
      SettingsTopic.plus ||
      SettingsTopic.rider ||
      SettingsTopic.appearance ||
      SettingsTopic.assistant ||
      SettingsTopic.mapsData ||
      SettingsTopic.about => true,
    };

String _title(AppLocalizations l10n, SettingsTopic topic) => switch (topic) {
  SettingsTopic.sync => l10n.settingsSync,
  SettingsTopic.plus => l10n.plusTitle,
  SettingsTopic.connections => l10n.settingsConnections,
  SettingsTopic.navigation => l10n.settingsNavigation,
  SettingsTopic.recording => l10n.settingsRecording,
  SettingsTopic.rider => l10n.settingsRiderAndBike,
  SettingsTopic.sensors => l10n.settingsSensors,
  SettingsTopic.appearance => l10n.settingsAppearance,
  SettingsTopic.assistant => l10n.settingsAi,
  SettingsTopic.mapsData => l10n.settingsMapsData,
  SettingsTopic.about => l10n.settingsAbout,
};

IconData _icon(SettingsTopic topic) => switch (topic) {
  SettingsTopic.sync => Icons.cloud_sync_outlined,
  SettingsTopic.plus => Icons.workspace_premium_outlined,
  SettingsTopic.connections => Icons.link,
  SettingsTopic.navigation => Icons.navigation_outlined,
  SettingsTopic.recording => Icons.radio_button_checked,
  SettingsTopic.rider => Icons.directions_bike_outlined,
  SettingsTopic.sensors => Icons.monitor_heart_outlined,
  SettingsTopic.appearance => Icons.palette_outlined,
  SettingsTopic.assistant => Icons.auto_awesome_outlined,
  SettingsTopic.mapsData => Icons.map_outlined,
  SettingsTopic.about => Icons.info_outline,
};

/// The overview's groups, in order, with their topics in order.
const List<(_Group, List<SettingsTopic>)> _groups = [
  (
    _Group.syncPlus,
    [SettingsTopic.sync, SettingsTopic.plus, SettingsTopic.connections],
  ),
  (
    _Group.riding,
    [
      SettingsTopic.navigation,
      SettingsTopic.recording,
      SettingsTopic.rider,
      SettingsTopic.sensors,
    ],
  ),
  (
    _Group.app,
    [
      SettingsTopic.appearance,
      SettingsTopic.assistant,
      SettingsTopic.mapsData,
      SettingsTopic.about,
    ],
  ),
];

enum _Group { syncPlus, riding, app }

/// The Settings tab: grouped rows, each opening one [SettingsTopicPage].
class SettingsScreen extends ConsumerWidget {
  /// Creates the overview.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final features = ref.watch(platformFeaturesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          for (final (group, topics) in _groups) ...[
            if (group != _Group.syncPlus) const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: SectionCaption(switch (group) {
                _Group.syncPlus => l10n.settingsGroupSyncPlus,
                _Group.riding => l10n.settingsGroupRiding,
                _Group.app => l10n.settingsGroupApp,
              }, accent: true),
            ),
            for (final topic in topics)
              if (_offered(topic, features, ref)) _TopicRow(topic),
          ],
        ],
      ),
    );
  }
}

/// One row of the overview: what the page holds, where cheap the state it
/// is in, and a way there.
class _TopicRow extends ConsumerWidget {
  const _TopicRow(this.topic);

  final SettingsTopic topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summary = _summary(context, ref, l10n);
    return ListTile(
      key: ValueKey<SettingsTopic>(topic),
      leading: Icon(_icon(topic)),
      title: Text(_title(l10n, topic)),
      subtitle: summary == null
          ? null
          : Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(
        Navigator.of(
          context,
        ).push(ColumnPageRoute<void>(builder: (_) => SettingsTopicPage(topic))),
      ),
    );
  }

  /// The state the page is in, from what the providers already hold;
  /// `null` where that would need more.
  String? _summary(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    switch (topic) {
      case SettingsTopic.sync:
        return syncServiceLabel(l10n, ref.watch(activeSyncServiceProvider));
      case SettingsTopic.plus:
        return ref.watch(plusEntitledProvider)
            ? l10n.plusActive
            : l10n.plusInactive;
      case SettingsTopic.connections:
        // As the section's tiles have it: not connected until known.
        final accounts =
            ref.watch(connectedAccountsProvider).value ??
            const <IntegrationService, ConnectedAccount>{};
        final connected = [
          for (final service in IntegrationService.values)
            if (accounts.containsKey(service)) serviceLabel(l10n, service),
        ];
        return connected.isEmpty
            ? l10n.connectionsNotConnected
            : connected.join(', ');
      case SettingsTopic.appearance:
        final mode = switch (ref.watch(appearanceSettingProvider).mode) {
          ThemeMode.system => l10n.appearanceModeSystem,
          ThemeMode.light => l10n.appearanceModeLight,
          ThemeMode.dark => l10n.appearanceModeDark,
        };
        final units = switch (ref.watch(unitSystemProvider)) {
          UnitSystem.metric => l10n.unitsMetric,
          UnitSystem.imperial => l10n.unitsImperial,
        };
        final language = languageName(Localizations.localeOf(context));
        return '$mode · $units · $language';
      case SettingsTopic.about:
        final info = ref.watch(packageInfoProvider).value;
        return info == null
            ? null
            : l10n.settingsVersion('${info.version}+${info.buildNumber}');
      case SettingsTopic.navigation ||
          SettingsTopic.recording ||
          SettingsTopic.rider ||
          SettingsTopic.sensors ||
          SettingsTopic.assistant ||
          SettingsTopic.mapsData:
        return null;
    }
  }
}

/// One settings page: [topic]'s sections under its title.
class SettingsTopicPage extends ConsumerWidget {
  /// Creates the page for [topic].
  const SettingsTopicPage(this.topic, {super.key});

  /// What the page holds.
  final SettingsTopic topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final features = ref.watch(platformFeaturesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_title(l10n, topic))),
      body: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: switch (topic) {
          SettingsTopic.sync => const [CloudSyncSection()],
          SettingsTopic.plus => const [PlusSettingsSection()],
          SettingsTopic.connections => const [ConnectionsSection()],
          SettingsTopic.navigation => const [NavigationSection()],
          SettingsTopic.recording => const [RecordingSection()],
          SettingsTopic.rider => const [RiderSection()],
          SettingsTopic.sensors => const [SensorsSection()],
          SettingsTopic.appearance => const [
            AppearanceSection(),
            UnitsSection(),
            LanguageSection(),
          ],
          SettingsTopic.assistant => const [AiSettingsSection()],
          SettingsTopic.mapsData => [
            if (features.offlineMapAreas) const OfflineEntry(),
            const SearchSettingsEntry(),
            if (features.routingServer) const _RoutingPreferenceSection(),
            const _ServerUrlsSection(),
          ],
          SettingsTopic.about => const [AboutSection()],
        },
      ),
    );
  }
}

/// Where routes are computed: the composite rule, or one of the two ends of
/// it. Stored in shared_preferences; the routing backend is rebuilt from it.
class _RoutingPreferenceSection extends ConsumerWidget {
  const _RoutingPreferenceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(routingPreferenceSettingProvider);
    final notifier = ref.read(routingPreferenceSettingProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.settingsRouting,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        RadioGroup<RoutingPreference>(
          groupValue: selected,
          onChanged: (value) =>
              unawaited(notifier.set(value ?? RoutingPreference.auto)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final preference in RoutingPreference.values)
                RadioListTile<RoutingPreference>(
                  value: preference,
                  title: Text(_title(l10n, preference)),
                  subtitle: Text(_detail(l10n, preference)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _title(AppLocalizations l10n, RoutingPreference preference) =>
      switch (preference) {
        RoutingPreference.auto => l10n.settingsRoutingAuto,
        RoutingPreference.onDeviceOnly => l10n.settingsRoutingOnDevice,
        RoutingPreference.serverOnly => l10n.settingsRoutingServer,
      };

  static String _detail(AppLocalizations l10n, RoutingPreference preference) =>
      switch (preference) {
        RoutingPreference.auto => l10n.settingsRoutingAutoDetail,
        RoutingPreference.onDeviceOnly => l10n.settingsRoutingOnDeviceDetail,
        RoutingPreference.serverOnly => l10n.settingsRoutingServerDetail,
      };
}

class _ServerUrlsSection extends ConsumerWidget {
  const _ServerUrlsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overrides = ref.watch(serverOverridesProvider);
    final config = ref.watch(appConfigProvider);
    final notifier = ref.read(serverOverridesProvider.notifier);
    final routingServer = ref.watch(platformFeaturesProvider).routingServer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.settingsServerUrls,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (routingServer)
          _UrlField(
            label: l10n.settingsBrouterUrl,
            value: overrides.brouterUrl,
            hint: config.brouterUrl,
            onChanged: notifier.setBrouterUrl,
          ),
        _UrlField(
          label: l10n.settingsPhotonUrl,
          value: overrides.photonUrl,
          hint: config.photonUrl,
          onChanged: notifier.setPhotonUrl,
        ),
        _UrlField(
          label: l10n.settingsApiUrl,
          value: overrides.apiUrl,
          hint: config.apiUrl,
          onChanged: notifier.setApiUrl,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            l10n.settingsServerUrlsHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              onPressed: overrides.isEmpty ? null : notifier.reset,
              child: Text(l10n.settingsResetServerUrls),
            ),
          ),
        ),
      ],
    );
  }
}

class _UrlField extends StatefulWidget {
  const _UrlField({
    required this.label,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String hint;
  final Future<void> Function(String) onChanged;

  @override
  State<_UrlField> createState() => _UrlFieldState();
}

class _UrlFieldState extends State<_UrlField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_UrlField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in sync when the value changes elsewhere, e.g. "Reset to defaults".
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint.isEmpty ? null : widget.hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => unawaited(widget.onChanged(value)),
        onTapOutside: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          unawaited(widget.onChanged(_controller.text));
        },
      ),
    );
  }
}
