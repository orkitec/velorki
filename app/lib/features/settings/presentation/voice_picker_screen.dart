import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/links/link_opener.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../navigation/application/turn_announcer.dart';
import '../../navigation/data/navigation_settings.dart';
import '../../navigation/data/turn_speaker.dart';
import '../../navigation/data/voice_catalogue_asset.dart';
import '../../navigation/domain/voice_catalogue.dart';
import '../../navigation/domain/voice_naming.dart';
import '../../navigation/domain/voice_option.dart';
import '../../navigation/domain/voice_ranking.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../../navigation/presentation/voice_labels.dart';
import '../data/units.dart';

/// Settings → Navigation → Speaking voice: which of the phone's voices says
/// the turns. Tapping a voice chooses it and says a sample cue in it; the
/// button on the row says the sample without changing the choice.
///
/// The engines name their voices for machines, so the rows show the name
/// from the bundled catalogue (or a numbered one) with the engine's own
/// identifier underneath. A voice that is synthesised online is left out
/// until the rider asks for it: on a ride without signal it says nothing.
class VoicePickerScreen extends ConsumerWidget {
  /// Creates the screen.
  const VoicePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(navigationSettingsProvider);
    final voices = ref.watch(availableVoicesProvider);
    final catalogue = ref.watch(voiceCatalogueProvider);
    final apple = Theme.of(context).platform == TargetPlatform.iOS;
    final named = describeVoices(
      voices.value ?? const <VoiceOption>[],
      catalogue: catalogue.value ?? const VoiceCatalogue.empty(),
      naming: namingFrom(l10n),
      apple: apple,
      // The phone's own locale, region included; the app's resolved locale
      // is only ever a language while the strings ship in one.
      preferredLocaleTag: WidgetsBinding.instance.platformDispatcher.locale
          .toLanguageTag(),
    );
    // What "System default" comes out as right now, worked out from the same
    // list the speaker ranks, so the row and the ride agree. Named from
    // [named] so it reads the way the rows below do.
    final resolved = bestVoiceFor(
      voices.value ?? const <VoiceOption>[],
      cueLocaleTag(),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsVoicePick)),
      body: voices.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _VoiceList(
              voices: named,
              chosen: settings.voiceId,
              apple: apple,
              resolvedId: resolved?.id,
            ),
    );
  }
}

class _VoiceList extends ConsumerStatefulWidget {
  const _VoiceList({
    required this.voices,
    required this.chosen,
    required this.apple,
    this.resolvedId,
  });

  final List<VoiceOption> voices;
  final String? chosen;
  final bool apple;

  /// The voice "System default" resolves to, or `null` when the choice is
  /// left to the engine.
  final String? resolvedId;

  @override
  ConsumerState<_VoiceList> createState() => _VoiceListState();
}

class _VoiceListState extends ConsumerState<_VoiceList> {
  bool _showOnline = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final online = widget.voices.where((voice) => voice.needsNetwork).toList();
    final shown = _showOnline
        ? widget.voices
        : widget.voices.where((voice) => !voice.needsNetwork).toList();
    // What the default resolves to, by the name the rows use.
    final resolved = widget.resolvedId == null
        ? null
        : widget.voices
              .where((voice) => voice.id == widget.resolvedId)
              .firstOrNull;
    // The card only helps where the rider can act on it: iOS keeps the good
    // voices behind a download, Android ships them with the engine. Nothing
    // resolved means the best voice for the language is the compact one.
    final needsBetter = widget.apple && widget.resolvedId == null;
    return ListView(
      padding: EdgeInsets.only(bottom: bottom + 24),
      children: [
        if (needsBetter) const _BetterVoicesCard(),
        if (_showOnline && online.isNotEmpty) const _NetworkNote(),
        ListTile(
          leading: Icon(
            widget.chosen == null
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
            color: widget.chosen == null ? theme.colorScheme.primary : null,
          ),
          title: Text(
            resolved == null
                ? l10n.settingsVoiceSystemDefault
                : l10n.settingsVoiceSystemDefaultNow(resolved.displayName),
          ),
          subtitle: Text(l10n.settingsVoiceSystemDefaultHint),
          onTap: () => unawaited(_choose(null)),
        ),
        for (final voice in shown)
          _VoiceTile(
            voice: voice,
            chosen: voice.id == widget.chosen,
            onTap: () => unawaited(_choose(voice.id)),
            onTry: () => unawaited(_try(voice)),
          ),
        if (widget.voices.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Text(
              l10n.settingsVoiceNone,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (online.isNotEmpty)
          SwitchListTile(
            value: _showOnline,
            title: Text(l10n.voiceShowOnline),
            onChanged: (value) => setState(() => _showOnline = value),
          ),
      ],
    );
  }

  /// Stores the choice, hands it to the speaker and says a sample in it.
  Future<void> _choose(String? id) async {
    await ref.read(navigationSettingsProvider.notifier).setVoiceId(id);
    final speaker = ref.read(turnSpeakerProvider);
    await speaker.stop();
    await speaker.selectVoice(id);
    await speaker.speak(_sample());
  }

  /// Says the sample in [voice] and goes back to the chosen one, so a rider
  /// can listen through the list without losing the voice they had.
  Future<void> _try(VoiceOption voice) async {
    final speaker = ref.read(turnSpeakerProvider);
    await speaker.stop();
    await speaker.selectVoice(voice.id);
    await speaker.speak(_sample());
    // Queued behind the sample by the speaker, so the cue is still said in
    // the voice that was tried.
    await speaker.selectVoice(ref.read(navigationSettingsProvider).voiceId);
  }

  /// The cue the samples say, in the rider's units.
  String _sample() => cuePhrase(
    const TurnCue(
      kind: CueKind.ahead,
      turn: TurnHint(pointIndex: 0, kind: TurnKind.left),
      distanceM: 200,
    ),
    ref.read(_l10nProvider),
    units: ref.read(unitSystemProvider),
  );
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
    required this.onTry,
  });

  final VoiceOption voice;
  final bool chosen;
  final VoidCallback onTap;
  final VoidCallback onTry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        chosen ? Icons.radio_button_checked : Icons.radio_button_off,
        color: chosen ? theme.colorScheme.primary : null,
      ),
      title: Text(voice.displayName),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            voice.rawIdentifier,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (voice.needsNetwork) const _NetworkChip(),
        ],
      ),
      trailing: TextButton(onPressed: onTry, child: Text(l10n.voiceTry)),
      onTap: onTap,
    );
  }
}

/// How to get a voice worth listening to on an iPhone.
///
/// Apple ships the compact voice and leaves the rest as a download, and
/// there is no link straight to the voices page; `app-settings:` is as close
/// as iOS lets an app get, which is why the way there is written out step by
/// step and the button says where it lands.
class _BetterVoicesCard extends ConsumerWidget {
  const _BetterVoicesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = languageNameOf(l10n, cueLocaleTag());
    final body = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSecondaryContainer,
    );
    // Apple has no link to the voices page, so the way there is spelled out.
    final steps = <String>[
      l10n.voiceBetterStep1,
      l10n.voiceBetterStep2,
      l10n.voiceBetterStep3,
      l10n.voiceBetterStep4(language),
      l10n.voiceBetterStep5,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.voiceBetterTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(l10n.voiceBetterBody(language), style: body),
              const SizedBox(height: 8),
              for (final (index, step) in steps.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text('${index + 1}.', style: body),
                      ),
                      Expanded(child: Text(step, style: body)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(l10n.voiceBetterAfter, style: body),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () => unawaited(
                    ref.read(linkOpenerProvider)(Uri.parse('app-settings:')),
                  ),
                  child: Text(l10n.voiceBetterOpenSettings),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.voiceBetterOpenSettingsHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
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
      label: Text(l10n.voiceNeedsNetwork),
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

/// Why the cloud matters, shown above the list once the online voices are in
/// it.
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
