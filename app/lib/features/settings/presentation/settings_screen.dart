import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/package_info_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        children: const [
          _SectionHeader.advanced(),
          _ServerUrlsSection(),
          Divider(height: 32),
          _SectionHeader.about(),
          _AboutSection(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader.advanced() : _about = false;
  const _SectionHeader.about() : _about = true;

  final bool _about;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        _about ? l10n.settingsAbout : l10n.settingsAdvanced,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
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

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(packageInfoProvider);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.appName),
          subtitle: Text(
            info.when(
              data: (i) =>
                  l10n.settingsVersion('${i.version}+${i.buildNumber}'),
              loading: () => l10n.settingsVersionUnknown,
              error: (_, _) => l10n.settingsVersionUnknown,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: Text(l10n.osmAttribution),
        ),
      ],
    );
  }
}
