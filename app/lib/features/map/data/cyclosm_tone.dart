import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../settings/data/appearance_controller.dart';

/// How the CyclOSM raster overlay is painted for one map look.
///
/// CyclOSM serves one set of tiles, drawn for a light background: laid over
/// the night or the black base map unchanged it glows, and the base map stops
/// reading as the map. The tiles cannot be re-rendered on the phone, so
/// MapLibre's raster paint is the only lever there is.
///
/// Two treatments are offered, because the trade-off is a matter of taste
/// ([OverlayDarkMode]). Inverting is the classic dark-mode trick: the raster
/// shader mixes every channel between [brightnessMin] and [brightnessMax], so
/// min 1 / max 0 turns the image inside out — white paper becomes the dark
/// ground, the ink becomes light — and a [hueRotate] of 180° puts the colours
/// the inversion moved to the far side of the wheel (blue water, green parks,
/// the red of a cycle route) back where they belong. Dimming instead keeps
/// CyclOSM's own colours and only pulls the brightness and the [saturation]
/// down. [contrast] takes the last of the glow off either way, and [opacity]
/// lets the base map's labels through.
///
/// The two brightness ends are each validated in 0..1 on their own — the
/// style spec sets no relation between them — so `min > max` is a legal style
/// and is exactly what does the inverting.
typedef RasterTone = ({
  double brightnessMin,
  double brightnessMax,
  double hueRotate,
  double saturation,
  double contrast,
  double opacity,
});

/// The light map, and every dark map the rider left [OverlayDarkMode.unchanged]:
/// the style-spec defaults, bar the slight transparency the overlay has always
/// been drawn with so the base map's labels show through.
const RasterTone lightCyclosmTone = (
  brightnessMin: 0.0,
  brightnessMax: 1.0,
  hueRotate: 0.0,
  saturation: 0.0,
  contrast: 0.0,
  opacity: 0.85,
);

/// The blue-grey night map, inverted: hue-corrected and calmed just enough
/// that the cycle network reads without glowing.
const RasterTone nightInvertedTone = (
  brightnessMin: 1.0,
  brightnessMax: 0.0,
  hueRotate: 180.0,
  saturation: -0.2,
  contrast: -0.1,
  opacity: 0.9,
);

/// The black map of a battery-saver ride, inverted: the same inversion, but
/// the whites it produces stop short of full brightness and the colour is
/// pulled further out, because every lit pixel there costs the ride.
const RasterTone blackInvertedTone = (
  brightnessMin: 0.85,
  brightnessMax: 0.0,
  hueRotate: 180.0,
  saturation: -0.4,
  contrast: -0.1,
  opacity: 0.85,
);

/// The night map, dimmed: CyclOSM's own colours, darker and calmer.
const RasterTone nightDimmedTone = (
  brightnessMin: 0.0,
  brightnessMax: 0.55,
  hueRotate: 0.0,
  saturation: -0.35,
  contrast: 0.0,
  opacity: 0.9,
);

/// The black map, dimmed: darker and greyer still.
const RasterTone blackDimmedTone = (
  brightnessMin: 0.0,
  brightnessMax: 0.35,
  hueRotate: 0.0,
  saturation: -0.6,
  contrast: 0.0,
  opacity: 0.85,
);

/// The tone the overlay is drawn with under [look] with [mode] chosen.
///
/// [MapLook.auto] is a light or a night map depending on the theme, so the
/// caller resolves it first (`resolveMapLook`); unresolved it is toned like
/// the light map, which is what an untoned overlay has always looked like.
RasterTone cyclosmToneFor(MapLook look, OverlayDarkMode mode) =>
    switch ((look, mode)) {
      // The light map needs nothing: the tiles were drawn for it.
      (MapLook.light || MapLook.auto, _) => lightCyclosmTone,
      (_, OverlayDarkMode.unchanged) => lightCyclosmTone,
      (MapLook.night, OverlayDarkMode.inverted) => nightInvertedTone,
      (MapLook.night, OverlayDarkMode.dimmed) => nightDimmedTone,
      (MapLook.black, OverlayDarkMode.inverted) => blackInvertedTone,
      (MapLook.black, OverlayDarkMode.dimmed) => blackDimmedTone,
    };

/// The raster paint of a tone.
extension RasterToneProperties on RasterTone {
  /// The tone as maplibre paint, plus [visibility] when the caller knows it
  /// (only `addLayer` does; a repaint leaves the visibility alone).
  ml.RasterLayerProperties layerProperties({String? visibility}) =>
      ml.RasterLayerProperties(
        rasterOpacity: opacity,
        rasterHueRotate: hueRotate,
        rasterBrightnessMin: brightnessMin,
        rasterBrightnessMax: brightnessMax,
        rasterSaturation: saturation,
        rasterContrast: contrast,
        visibility: visibility,
      );
}
