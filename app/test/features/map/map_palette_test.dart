import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';
import 'package:velorki/features/map/presentation/map_view.dart';

void main() {
  group('MapPalette.fromTheme', () {
    test('draws the route in the chosen accent', () {
      final ember = MapPalette.fromTheme(buildDarkTheme(AccentPreset.ember));

      expect(ember.routeMain, '#FF5A1F');
      expect(ember.routeMain, VelorkiColors.hex(AccentPreset.ember.route));
      // The route colour is the same on both map styles.
      expect(
        MapPalette.fromTheme(buildLightTheme(AccentPreset.ember)).routeMain,
        '#FF5A1F',
      );
    });

    test('every preset gets its own route colour', () {
      final seen = <String>{};
      for (final preset in AccentPreset.values) {
        final palette = MapPalette.fromTheme(buildDarkTheme(preset));
        expect(palette.routeMain, VelorkiColors.hex(preset.route));
        seen.add(palette.routeMain);
      }
      expect(seen, hasLength(AccentPreset.values.length));
    });

    test('the label colour follows the map style', () {
      final light = MapPalette.fromTheme(buildLightTheme());
      final dark = MapPalette.fromTheme(buildDarkTheme());

      expect(light.waypointLabel, isNot(dark.waypointLabel));
      // Both are hex strings maplibre accepts.
      for (final colour in [light.waypointLabel, dark.waypointLabel]) {
        expect(colour, matches(RegExp(r'^#[0-9A-F]{6}$')));
      }
      // The casing under the route is the ink of its own mode.
      expect(light.routeMainCasing, isNot(dark.routeMainCasing));
      // A palette is built as a whole: the two differ.
      expect(light, isNot(dark));
    });

    test('reads the extension, so every field is a hex string', () {
      final palette = MapPalette.fromTheme(buildDarkTheme(AccentPreset.berry));
      final hex = RegExp(r'^#[0-9A-F]{6}([0-9A-F]{2})?$');

      for (final colour in <String>[
        palette.routeMain,
        palette.routeMainCasing,
        palette.routeAlternative,
        palette.routePreview,
        palette.track,
        palette.waypointStart,
        palette.waypointVia,
        palette.waypointEnd,
        palette.waypointStroke,
        palette.waypointLabel,
        palette.waypointLabelHalo,
        palette.positionDot,
        palette.positionAccuracy,
      ]) {
        expect(colour, matches(hex), reason: colour);
      }
    });
  });

  group('MapPalette equality', () {
    test('the classic palette equals itself', () {
      expect(const MapPalette.classic(), const MapPalette.classic());
      expect(
        const MapPalette.classic().hashCode,
        const MapPalette.classic().hashCode,
      );
    });

    test('two themed palettes of the same theme are equal', () {
      expect(
        MapPalette.fromTheme(buildDarkTheme(AccentPreset.glacier)),
        MapPalette.fromTheme(buildDarkTheme(AccentPreset.glacier)),
      );
      expect(
        MapPalette.fromTheme(buildDarkTheme(AccentPreset.glacier)),
        isNot(MapPalette.fromTheme(buildDarkTheme(AccentPreset.volt))),
      );
      expect(
        MapPalette.fromTheme(buildDarkTheme()),
        isNot(const MapPalette.classic()),
      );
    });
  });

  group('mapStyleUrlFor', () {
    test('falls back per brightness when nothing is configured', () {
      const config = AppConfig();

      expect(mapStyleUrlFor(config, Brightness.dark), fallbackMapStyleUrlDark);
      expect(mapStyleUrlFor(config, Brightness.dark), contains('/dark'));
      expect(mapStyleUrlFor(config, Brightness.light), fallbackMapStyleUrl);
    });

    test('prefers the configured URLs', () {
      const config = AppConfig(
        mapStyleUrl: 'https://tiles.example.org/day.json',
        mapStyleUrlDark: 'https://tiles.example.org/night.json',
      );

      expect(
        mapStyleUrlFor(config, Brightness.light),
        'https://tiles.example.org/day.json',
      );
      expect(
        mapStyleUrlFor(config, Brightness.dark),
        'https://tiles.example.org/night.json',
      );
    });

    test('a build with only a light style still gets a dark one', () {
      const config = AppConfig(
        mapStyleUrl: 'https://tiles.example.org/day.json',
      );

      expect(
        mapStyleUrlFor(config, Brightness.light),
        'https://tiles.example.org/day.json',
      );
      expect(mapStyleUrlFor(config, Brightness.dark), fallbackMapStyleUrlDark);
    });
  });
}
