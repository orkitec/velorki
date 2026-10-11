import '../domain/weather_map.dart';
import 'cyclosm_tone.dart';

// How the weather layers are painted, per map look. Kept together so they
// can be tuned in one place.

/// The rain radar: the services' own colours, slightly see-through so the
/// map's roads stay readable under a shower.
const RasterTone radarTone = (
  brightnessMin: 0.0,
  brightnessMax: 1.0,
  hueRotate: 0.0,
  saturation: 0.0,
  contrast: 0.0,
  opacity: 0.75,
);

/// The soft rain radar: opaque as a layer, since its image's alpha already
/// carries how see-through each shower is (see `softenRadarPixels`).
const RasterTone radarSoftTone = (
  brightnessMin: 0.0,
  brightnessMax: 1.0,
  hueRotate: 0.0,
  saturation: 0.0,
  contrast: 0.0,
  opacity: 1.0,
);

/// The clouds on the light map. The image is already white cloud on a clear
/// ground (see `whitenCloudPixels`); pulling its white down to a very light
/// grey keeps clouds visible over the light map's white areas.
const RasterTone cloudsLightTone = (
  brightnessMin: 0.0,
  brightnessMax: 0.88,
  hueRotate: 0.0,
  saturation: 0.0,
  contrast: 0.0,
  opacity: 1.0,
);

/// The clouds on the night and the black map: a softer white, so they do
/// not glare.
const RasterTone cloudsDarkTone = (
  brightnessMin: 0.0,
  brightnessMax: 0.8,
  hueRotate: 0.0,
  saturation: 0.0,
  contrast: 0.0,
  opacity: 0.9,
);

/// The paint of a weather layer of [kind] on a light or a [dark] map look,
/// with the source's own [opacity] where it names one; a radar drawn as one
/// processed [image] is the soft radar.
RasterTone weatherTone(
  WeatherKind kind, {
  required bool dark,
  double? opacity,
  bool image = false,
}) {
  final tone = switch (kind) {
    WeatherKind.radar => image ? radarSoftTone : radarTone,
    WeatherKind.clouds => dark ? cloudsDarkTone : cloudsLightTone,
  };
  if (opacity == null) return tone;
  return (
    brightnessMin: tone.brightnessMin,
    brightnessMax: tone.brightnessMax,
    hueRotate: tone.hueRotate,
    saturation: tone.saturation,
    contrast: tone.contrast,
    opacity: opacity,
  );
}
