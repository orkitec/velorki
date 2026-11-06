import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/navigation/data/navigation_settings.dart';
import '../../../features/navigation/data/turn_speaker.dart';
import '../../../features/navigation/data/voice_catalogue_asset.dart';
import '../../../features/navigation/domain/voice_catalogue.dart';
import '../../../features/navigation/domain/voice_naming.dart';
import '../../../features/navigation/domain/voice_option.dart';
import '../../../features/navigation/presentation/voice_labels.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../navigation/presentation/navigation_toggles.dart';
import '../../shared/presentation/wide_panel.dart';
import 'voice_picker_screen.dart';

/// Settings → Navigation: the turn directions, whether they are spoken, how
/// far ahead, what other audio does meanwhile, and whether leaving the route
/// plans a new way back onto it.
class NavigationSection extends ConsumerWidget {
  /// Creates the section.
  const NavigationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(navigationSettingsProvider);
    final controller = ref.read(navigationSettingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Turn directions and voice; re-routing follows at the end so the
        // voice's own rows sit next to its switch.
        const NavigationToggles(only: NavigationToggle.turnsAndVoice),
        // Which voice: the chosen one by name, or the phone's own.
        ListTile(
          enabled: settings.turns && settings.voice,
          title: Text(l10n.settingsVoicePick),
          subtitle: Text(_voiceName(context, ref, settings.voiceId, l10n)),
          trailing: const Icon(Icons.chevron_right),
          onTap: settings.turns && settings.voice
              ? () => Navigator.of(context).push(
                  ColumnPageRoute<void>(
                    builder: (_) => const VoicePickerScreen(),
                  ),
                )
              : null,
        ),
        // How far ahead a turn is spoken, in seconds of travel; it only
        // matters while there is a voice.
        ListTile(
          enabled: settings.turns && settings.voice,
          title: Text(l10n.settingsTurnLead),
          subtitle: Text(l10n.settingsTurnLeadHint(settings.leadSeconds)),
        ),
        Slider(
          value: settings.leadSeconds.toDouble(),
          min: minLeadSeconds.toDouble(),
          max: maxLeadSeconds.toDouble(),
          divisions: maxLeadSeconds - minLeadSeconds,
          label: l10n.settingsTurnLeadValue(settings.leadSeconds),
          onChanged: settings.turns && settings.voice
              ? (value) => unawaited(controller.setLeadSeconds(value.round()))
              : null,
        ),
        // What music and podcasts from other apps do while a turn is
        // said; also only while there is a voice. Applies from the next
        // instruction on.
        ListTile(
          enabled: settings.turns && settings.voice,
          title: Text(l10n.settingsOtherAudio),
        ),
        RadioGroup<InstructionAudio>(
          groupValue: settings.otherAudio,
          onChanged: (value) {
            if (value != null && settings.turns && settings.voice) {
              unawaited(controller.setOtherAudio(value));
            }
          },
          child: Column(
            children: [
              for (final value in InstructionAudio.values)
                RadioListTile<InstructionAudio>(
                  value: value,
                  enabled: settings.turns && settings.voice,
                  title: Text(_otherAudioLabel(value, l10n)),
                  subtitle: Text(_otherAudioHint(value, l10n)),
                ),
            ],
          ),
        ),
        const NavigationToggles(only: NavigationToggle.reroute),
      ],
    );
  }
}

String _otherAudioLabel(InstructionAudio value, AppLocalizations l10n) =>
    switch (value) {
      InstructionAudio.pausePodcasts => l10n.settingsOtherAudioPausePodcasts,
      InstructionAudio.lowerVolume => l10n.settingsOtherAudioLowerVolume,
    };

String _otherAudioHint(InstructionAudio value, AppLocalizations l10n) =>
    switch (value) {
      InstructionAudio.pausePodcasts =>
        l10n.settingsOtherAudioPausePodcastsHint,
      InstructionAudio.lowerVolume => l10n.settingsOtherAudioLowerVolumeHint,
    };

/// The name of the voice with [id], or the default's name while the list is
/// still loading or the voice is gone. Named the same way the picker names
/// it, so the row and the list agree.
String _voiceName(
  BuildContext context,
  WidgetRef ref,
  String? id,
  AppLocalizations l10n,
) {
  if (id == null) return l10n.settingsVoiceSystemDefault;
  final voices = ref.watch(availableVoicesProvider).value;
  final catalogue = ref.watch(voiceCatalogueProvider).value;
  final named = describeVoices(
    voices ?? const <VoiceOption>[],
    catalogue: catalogue ?? const VoiceCatalogue.empty(),
    naming: namingFrom(l10n),
    apple: Theme.of(context).platform == TargetPlatform.iOS,
  );
  for (final voice in named) {
    if (voice.id == id) return voice.displayName;
  }
  return l10n.settingsVoiceSystemDefault;
}
