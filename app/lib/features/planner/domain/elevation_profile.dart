import 'package:velorki_geo/velorki_geo.dart';

/// One point of the elevation profile: how far along the route it is and how
/// high.
class ElevationSample {
  /// Creates a sample.
  const ElevationSample(this.distanceM, this.elevationM);

  /// Distance from the start in metres.
  final double distanceM;

  /// Elevation in metres.
  final double elevationM;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElevationSample &&
          other.distanceM == distanceM &&
          other.elevationM == elevationM;

  @override
  int get hashCode => Object.hash(distanceM, elevationM);

  @override
  String toString() =>
      'ElevationSample(${distanceM.round()} m, ${elevationM.round()} m)';
}

/// The most points the chart ever draws.
const int elevationProfileMaxPoints = 500;

/// Turns a route geometry into a drawable elevation profile.
///
/// Distances are cumulative over the whole geometry, so points without an
/// elevation still push the ones after them along the x axis. The result is
/// thinned to at most [maxPoints] samples — a 200 km route has tens of
/// thousands of points and fl_chart draws every one of them — keeping the
/// first and the last so the profile still spans the whole route.
List<ElevationSample> elevationProfile(
  List<TrackPoint> geometry, {
  int maxPoints = elevationProfileMaxPoints,
}) {
  if (geometry.isEmpty) return const <ElevationSample>[];
  final distances = cumulativeDistancesMeters(
    geometry.map((p) => p.pos).toList(growable: false),
  );
  final samples = <ElevationSample>[];
  for (var i = 0; i < geometry.length; i++) {
    final ele = geometry[i].ele;
    if (ele == null) continue;
    samples.add(ElevationSample(distances[i], ele));
  }
  return downsampleElevation(samples, maxPoints: maxPoints);
}

/// Thins [samples] to at most [maxPoints], keeping the first and the last.
List<ElevationSample> downsampleElevation(
  List<ElevationSample> samples, {
  int maxPoints = elevationProfileMaxPoints,
}) {
  if (maxPoints < 2) {
    return samples.isEmpty ? samples : <ElevationSample>[samples.first];
  }
  if (samples.length <= maxPoints) return samples;
  final stride = (samples.length / maxPoints).ceil();
  final out = <ElevationSample>[];
  for (var i = 0; i < samples.length; i += stride) {
    out.add(samples[i]);
  }
  if (out.last != samples.last) out.add(samples.last);
  return out;
}
