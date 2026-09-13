import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/theme.dart';

/// The WCAG relative luminance of one 8-bit channel.
double _channel(int value) {
  final c = value / 255;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

/// The WCAG 2.x relative luminance of [color], alpha ignored.
double _luminance(Color color) {
  final argb = color.toARGB32();
  return 0.2126 * _channel((argb >> 16) & 0xFF) +
      0.7152 * _channel((argb >> 8) & 0xFF) +
      0.0722 * _channel(argb & 0xFF);
}

/// The WCAG contrast ratio between [a] and [b], between 1 and 21.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('every preset builds a complete theme', () {
    for (final preset in AccentPreset.values) {
      for (final brightness in Brightness.values) {
        final dark = brightness == Brightness.dark;
        test('${preset.name} ${brightness.name}', () {
          final theme = dark ? buildDarkTheme(preset) : buildLightTheme(preset);

          expect(theme.brightness, brightness);
          expect(theme.colorScheme.brightness, brightness);
          // The extension is what every screen reads for the map and the
          // glass panels; a theme without it crashes on first paint.
          expect(theme.extension<VelorkiColors>(), isNotNull);
          expect(theme.velorki.accent, dark ? preset.dark : preset.light);
          expect(theme.velorki.routeMain, preset.route);
          expect(theme.colorScheme.primary, dark ? preset.dark : preset.light);

          // The bundled typefaces, not the platform default.
          expect(theme.textTheme.bodyMedium?.fontFamily, velorkiBodyFont);
          expect(
            theme.textTheme.headlineMedium?.fontFamily,
            velorkiDisplayFont,
          );

          // Text on a filled button has to stay readable.
          final ratio = _contrast(
            theme.colorScheme.primary,
            theme.colorScheme.onPrimary,
          );
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'primary/onPrimary of ${preset.name} ${brightness.name} is '
                '${ratio.toStringAsFixed(2)}:1',
          );
        });
      }
    }
  });

  test('the text extensions use the display and body faces', () {
    final text = buildDarkTheme().textTheme;

    expect(text.statHero.fontFamily, velorkiDisplayFont);
    expect(text.statLarge.fontFamily, velorkiDisplayFont);
    expect(text.statMedium.fontFamily, velorkiDisplayFont);
    expect(text.overline.fontFamily, velorkiBodyFont);
    // The hero figure is the biggest thing on the record screen.
    expect(text.statHero.fontSize, greaterThan(text.statLarge.fontSize!));
    expect(text.statLarge.fontSize, greaterThan(text.statMedium.fontSize!));
  });

  test('an unknown accent name falls back to volt', () {
    expect(AccentPreset.fromName('nope'), AccentPreset.volt);
    expect(AccentPreset.fromName(null), AccentPreset.volt);
    expect(AccentPreset.fromName(''), AccentPreset.volt);
    for (final preset in AccentPreset.values) {
      expect(AccentPreset.fromName(preset.name), preset);
    }
  });

  test('colours are handed to maplibre as #RRGGBB', () {
    expect(VelorkiColors.hex(const Color(0xFF7ED321)), '#7ED321');
    expect(VelorkiColors.hex(const Color(0xFF000000)), '#000000');
    expect(VelorkiColors.hex(const Color(0xFFFFFFFF)), '#FFFFFF');
    // The alpha channel is dropped, not spilled into the string.
    expect(VelorkiColors.hex(const Color(0x330B0D10)), '#0B0D10');
  });

  test('the two brightnesses of one preset are different themes', () {
    final light = buildLightTheme(AccentPreset.glacier);
    final dark = buildDarkTheme(AccentPreset.glacier);

    expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
    expect(light.velorki.glass, isNot(dark.velorki.glass));
    // The route keeps its colour across both map styles.
    expect(light.velorki.routeMain, dark.velorki.routeMain);
  });
}
