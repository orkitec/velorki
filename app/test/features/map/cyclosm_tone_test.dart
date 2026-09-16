import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/cyclosm_tone.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';

void main() {
  group('cyclosmToneFor', () {
    test('leaves the light map alone whatever the dark-map choice is', () {
      for (final mode in OverlayDarkMode.values) {
        for (final look in <MapLook>[MapLook.light, MapLook.auto]) {
          expect(cyclosmToneFor(look, mode), lightCyclosmTone, reason: '$mode');
        }
      }
      // The light tone is the style-spec default bar the transparency the
      // overlay has always had.
      expect(lightCyclosmTone.brightnessMin, 0.0);
      expect(lightCyclosmTone.brightnessMax, 1.0);
      expect(lightCyclosmTone.hueRotate, 0.0);
      expect(lightCyclosmTone.saturation, 0.0);
      expect(lightCyclosmTone.contrast, 0.0);
      expect(lightCyclosmTone.opacity, 0.85);
    });

    test('inverts the overlay on the dark maps by default', () {
      expect(
        cyclosmToneFor(MapLook.night, OverlayDarkMode.inverted),
        nightInvertedTone,
      );
      expect(
        cyclosmToneFor(MapLook.black, OverlayDarkMode.inverted),
        blackInvertedTone,
      );
      // min above max is what turns the image inside out, and the hue
      // rotation puts the colours back.
      for (final tone in <RasterTone>[nightInvertedTone, blackInvertedTone]) {
        expect(tone.brightnessMin, greaterThan(tone.brightnessMax));
        expect(tone.hueRotate, 180.0);
        expect(tone.saturation, lessThan(0));
      }
      // The black map of a battery-saver ride stays the darker of the two.
      expect(
        blackInvertedTone.brightnessMin,
        lessThan(nightInvertedTone.brightnessMin),
      );
      expect(
        blackInvertedTone.saturation,
        lessThan(nightInvertedTone.saturation),
      );
    });

    test('dims without inverting when the rider asks for that', () {
      expect(
        cyclosmToneFor(MapLook.night, OverlayDarkMode.dimmed),
        nightDimmedTone,
      );
      expect(
        cyclosmToneFor(MapLook.black, OverlayDarkMode.dimmed),
        blackDimmedTone,
      );
      for (final tone in <RasterTone>[nightDimmedTone, blackDimmedTone]) {
        expect(tone.brightnessMin, lessThan(tone.brightnessMax));
        expect(tone.hueRotate, 0.0);
      }
      expect(nightDimmedTone.brightnessMax, 0.55);
      expect(nightDimmedTone.saturation, -0.35);
      expect(nightDimmedTone.opacity, 0.9);
      expect(blackDimmedTone.brightnessMax, 0.35);
      expect(blackDimmedTone.saturation, -0.6);
      expect(blackDimmedTone.opacity, 0.85);
    });

    test('draws the overlay untouched when the rider wants it that way', () {
      for (final look in MapLook.values) {
        expect(
          cyclosmToneFor(look, OverlayDarkMode.unchanged),
          lightCyclosmTone,
          reason: '$look',
        );
      }
    });
  });

  group('layerProperties', () {
    test('writes every raster paint property maplibre understands', () {
      expect(nightInvertedTone.layerProperties().toJson(), <String, dynamic>{
        'raster-opacity': 0.9,
        'raster-hue-rotate': 180.0,
        'raster-brightness-min': 1.0,
        'raster-brightness-max': 0.0,
        'raster-saturation': -0.2,
        'raster-contrast': -0.1,
      });
    });

    test('carries the visibility only when the caller knows it', () {
      expect(
        lightCyclosmTone.layerProperties(visibility: 'none').toJson(),
        containsPair('visibility', 'none'),
      );
      // A repaint leaves the visibility where it is.
      expect(
        lightCyclosmTone.layerProperties().toJson().keys,
        isNot(contains('visibility')),
      );
    });
  });
}
