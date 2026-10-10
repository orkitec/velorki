import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/appearance_controller.dart';

/// Settings → Appearance: light/dark/system, the map, the bar's glass and
/// the accent colour.
class AppearanceSection extends ConsumerWidget {
  /// Creates the section.
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appearance = ref.watch(appearanceSettingProvider);
    final controller = ref.read(appearanceSettingProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.appearanceMode, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.brightness_auto_outlined),
                label: _SegmentLabel(l10n.appearanceModeSystem),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_outlined),
                label: _SegmentLabel(l10n.appearanceModeLight),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode_outlined),
                label: _SegmentLabel(l10n.appearanceModeDark),
              ),
            ],
            selected: {appearance.mode},
            onSelectionChanged: (selection) =>
                unawaited(controller.setMode(selection.single)),
          ),
          const SizedBox(height: 20),
          Text(l10n.appearanceMap, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          SegmentedButton<MapLook>(
            showSelectedIcon: false,
            segments: [
              for (final look in MapLook.values)
                ButtonSegment(
                  value: look,
                  label: _SegmentLabel(mapLookLabel(l10n, look)),
                ),
            ],
            selected: {appearance.mapLook},
            onSelectionChanged: (selection) =>
                unawaited(controller.setMapLook(selection.single)),
          ),
          // Only the online cycle map: its tiles are pictures drawn for a
          // light map. The offline one has its own colours for dark maps.
          const SizedBox(height: 20),
          Text(
            l10n.appearanceOverlayDarkTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          SegmentedButton<OverlayDarkMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in OverlayDarkMode.values)
                ButtonSegment(
                  value: mode,
                  label: _SegmentLabel(overlayDarkLabel(l10n, mode)),
                ),
            ],
            selected: {appearance.overlayDark},
            onSelectionChanged: (selection) =>
                unawaited(controller.setOverlayDark(selection.single)),
          ),
          const SizedBox(height: 20),
          Text(l10n.appearanceGlass, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          SegmentedButton<BarStyle>(
            showSelectedIcon: false,
            segments: [
              for (final style in BarStyle.values)
                ButtonSegment(
                  value: style,
                  label: _SegmentLabel(barStyleLabel(l10n, style)),
                ),
            ],
            selected: {appearance.barStyle},
            onSelectionChanged: (selection) =>
                unawaited(controller.setBarStyle(selection.single)),
          ),
          const SizedBox(height: 8),
          Text(l10n.appearanceGlassHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          Text(l10n.appearanceAccent, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final preset in AccentPreset.values) ...[
                Expanded(
                  child: _AccentSwatch(
                    preset: preset,
                    label: accentLabel(l10n, preset),
                    selected: preset == appearance.accent,
                    onTap: () => unawaited(controller.setAccent(preset)),
                  ),
                ),
                if (preset != AccentPreset.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The localised name of a map look.
String mapLookLabel(AppLocalizations l10n, MapLook look) => switch (look) {
  MapLook.auto => l10n.mapLookAuto,
  MapLook.light => l10n.mapLookLight,
  MapLook.night => l10n.mapLookNight,
  MapLook.black => l10n.mapLookBlack,
};

/// The localised name of a dark-map treatment for the cycling overlay.
String overlayDarkLabel(AppLocalizations l10n, OverlayDarkMode mode) =>
    switch (mode) {
      OverlayDarkMode.inverted => l10n.appearanceOverlayDarkInverted,
      OverlayDarkMode.dimmed => l10n.appearanceOverlayDarkDimmed,
      OverlayDarkMode.unchanged => l10n.appearanceOverlayDarkUnchanged,
    };

/// The localised name of a bar style.
String barStyleLabel(AppLocalizations l10n, BarStyle style) => switch (style) {
  BarStyle.solid => l10n.appearanceBarSolid,
  BarStyle.transparent => l10n.appearanceBarTransparent,
  BarStyle.subtle => l10n.appearanceBarSubtle,
  BarStyle.clear => l10n.appearanceBarClear,
};

/// The localised name of an accent preset.
String accentLabel(AppLocalizations l10n, AccentPreset preset) =>
    switch (preset) {
      AccentPreset.volt => l10n.accentVolt,
      AccentPreset.ember => l10n.accentEmber,
      AccentPreset.glacier => l10n.accentGlacier,
      AccentPreset.berry => l10n.accentBerry,
      AccentPreset.forest => l10n.accentForest,
    };

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.preset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AccentPreset preset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final color = dark ? preset.dark : preset.light;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? color : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: dark ? const Color(0xFF0B0D10) : Colors.white,
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A segment's label on one line: in a language whose word is too long for
/// its share of the row it is set a little smaller rather than wrapped or
/// cut off.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, maxLines: 1, softWrap: false),
  );
}
