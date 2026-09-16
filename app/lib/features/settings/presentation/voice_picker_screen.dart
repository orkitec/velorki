import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../navigation/application/turn_announcer.dart';
import '../../navigation/data/navigation_settings.dart';
import '../../navigation/data/turn_speaker.dart';
import '../../navigation/domain/voice_option.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../data/units.dart';

/// Settings → Navigation → Speaking voice: which of the phone's voices says
/// the turns. Tapping a voice chooses it and says a sample cue in it.
///
/// A voice that is synthesised online is marked with a cloud and explained
/// at the top: on a ride without signal such a voice says nothing.
class VoicePickerScreen extends ConsumerWidget {
  /// Creates the screen.
  const VoicePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(navigationSettingsProvider);
    final voices = ref.watch(availableVoicesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsVoicePick)),
      body: voices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _VoiceList(voices: const [], chosen: settings.voiceId),
        data: (list) => _VoiceList(voices: list, chosen: settings.voiceId),
      ),
    );
  }
}

class _VoiceList extends ConsumerWidget {
  const _VoiceList({required this.voices, required this.chosen});

  final List<VoiceOption> voices;
  final String? chosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.only(bottom: bottom + 24),
      children: [
        if (voices.any((voice) => voice.needsNetwork)) const _NetworkNote(),
        ListTile(
          leading: Icon(
            chosen == null
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
            color: chosen == null ? theme.colorScheme.primary : null,
          ),
          title: Text(l10n.settingsVoiceSystemDefault),
          subtitle: Text(l10n.settingsVoiceSystemDefaultHint),
          onTap: () => unawaited(_choose(ref, null)),
        ),
        for (final voice in voices)
          _VoiceTile(
            voice: voice,
            chosen: voice.id == chosen,
            onTap: () => unawaited(_choose(ref, voice.id)),
          ),
        if (voices.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Text(
              l10n.settingsVoiceNone,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// Stores the choice, hands it to the speaker and says a sample in it.
  Future<void> _choose(WidgetRef ref, String? id) async {
    final l10n = ref.read(_l10nProvider);
    await ref.read(navigationSettingsProvider.notifier).setVoiceId(id);
    final speaker = ref.read(turnSpeakerProvider);
    await speaker.stop();
    await speaker.selectVoice(id);
    await speaker.speak(
      cuePhrase(
        const TurnCue(
          kind: CueKind.ahead,
          turn: TurnHint(pointIndex: 0, kind: TurnKind.left),
          distanceM: 100,
        ),
        l10n,
        units: ref.read(unitSystemProvider),
      ),
    );
  }
}

/// The strings for the sample cue, looked up the same way the ride does.
final _l10nProvider = Provider<AppLocalizations>(
  (ref) => lookupAppLocalizations(Locale(cueLocaleTag().split('-').first)),
);

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.voice,
    required this.chosen,
    required this.onTap,
  });

  final VoiceOption voice;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quality = switch (voice.quality) {
      VoiceQuality.premium => l10n.settingsVoiceQualityPremium,
      VoiceQuality.enhanced => l10n.settingsVoiceQualityEnhanced,
      VoiceQuality.standard => null,
    };
    return ListTile(
      leading: Icon(
        chosen ? Icons.radio_button_checked : Icons.radio_button_off,
        color: chosen ? theme.colorScheme.primary : null,
      ),
      title: Text(voice.name),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            quality == null ? voice.localeTag : '${voice.localeTag} · $quality',
          ),
          if (voice.needsNetwork) const _NetworkChip(),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// The cloud that marks an online voice.
class _NetworkChip extends StatelessWidget {
  const _NetworkChip();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(
        Icons.cloud_outlined,
        size: 16,
        color: theme.colorScheme.onErrorContainer,
      ),
      label: Text(l10n.settingsVoiceNeedsInternet),
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onErrorContainer,
      ),
      backgroundColor: theme.colorScheme.errorContainer,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

/// Why the cloud matters, shown once above the list.
class _NetworkNote extends StatelessWidget {
  const _NetworkNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_outlined,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsVoiceNetworkTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.settingsVoiceNetworkHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
