import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../features/assistant/presentation/ai_settings_section.dart';
import '../../../features/integrations/presentation/connections_section.dart';
import '../../../features/map/presentation/map_strings.dart';
import '../../../features/map/presentation/offline_regions_screen.dart';
import '../../../features/routing_tiles/data/routing_preference_controller.dart';
import '../../../features/routing_tiles/domain/routing_preference.dart';
import '../../../features/routing_tiles/presentation/routing_tiles_screen.dart';
import '../../../features/subscription/presentation/plus_settings_section.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import 'about_section.dart';
import 'appearance_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: const [
          _SectionHeader.appearance(),
          AppearanceSection(),
          Divider(height: 32),
          _SectionHeader.subscription(),
          PlusSettingsSection(),
          Divider(height: 32),
          _SectionHeader.connections(),
          ConnectionsSection(),
          Divider(height: 32),
          _SectionHeader.ai(),
          AiSettingsSection(),
          Divider(height: 32),
          _SectionHeader.advanced(),
          _OfflineMapsTile(),
          _RoutingTilesTile(),
          _RoutingPreferenceSection(),
          _ServerUrlsSection(),
          Divider(height: 32),
          _SectionHeader.about(),
          AboutSection(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader.appearance() : _section = _Section.appearance;
  const _SectionHeader.subscription() : _section = _Section.subscription;
  const _SectionHeader.connections() : _section = _Section.connections;
  const _SectionHeader.ai() : _section = _Section.ai;
  const _SectionHeader.advanced() : _section = _Section.advanced;
  const _SectionHeader.about() : _section = _Section.about;

  final _Section _section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: SectionCaption(switch (_section) {
        _Section.appearance => l10n.settingsAppearance,
        _Section.subscription => l10n.settingsSubscription,
        _Section.connections => l10n.settingsConnections,
        _Section.ai => l10n.settingsAi,
        _Section.advanced => l10n.settingsAdvanced,
        _Section.about => l10n.settingsAbout,
      }, accent: true),
    );
  }
}

enum _Section { appearance, subscription, connections, ai, advanced, about }

/// Entry point into the map feature's offline regions screen.
///
/// Pushed with the root [Navigator] rather than go_router: offline maps are a
/// detail of the map feature and do not need a route of their own.
class _OfflineMapsTile extends StatelessWidget {
  const _OfflineMapsTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.download_for_offline_outlined),
      title: const Text(MapStrings.offlineRegionsTitle),
      subtitle: const Text(MapStrings.offlineRegionsSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OfflineRegionsScreen()),
      ),
    );
  }
}

/// Entry point into the on-device routing data, pushed the same way as the
/// offline maps screen. No map is alive here, so the screen offers the
/// planner's tiles and the manifest, but not "the visible area".
class _RoutingTilesTile extends ConsumerWidget {
  const _RoutingTilesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.grid_on_outlined),
      title: Text(l10n.routingTilesTitle),
      subtitle: Text(l10n.routingTilesSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RoutingTilesScreen()),
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
