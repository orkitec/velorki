import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/elevation_profile.dart';
import 'package:velorki_geo/velorki_geo.dart';

List<TrackPoint> _geometry(int count, {bool withElevation = true}) =>
    List<TrackPoint>.generate(
      count,
      (i) => TrackPoint(
        LatLng(48.0 + i * 0.001, 11.0),
        ele: withElevation ? 500 + (i % 50).toDouble() : null,
      ),
      growable: false,
    );

void main() {
  test('an empty geometry has no profile', () {
    expect(elevationProfile(const []), isEmpty);
  });

  test(
    'points without elevation are skipped but still advance the distance',
    () {
      final geometry = [
        TrackPoint(const LatLng(48.0, 11.0), ele: 500),
        const TrackPoint(LatLng(48.01, 11.0)),
        TrackPoint(const LatLng(48.02, 11.0), ele: 520),
      ];

      final profile = elevationProfile(geometry);

      expect(profile, hasLength(2));
      expect(profile.first.distanceM, 0);
      expect(profile.last.elevationM, 520);
      // The skipped middle point still counts towards the distance.
      expect(profile.last.distanceM, greaterThan(2000));
    },
  );

  test('a short route keeps every point', () {
    final profile = elevationProfile(_geometry(120));
    expect(profile, hasLength(120));
  });

  test('a long route is downsampled to at most 500 points', () {
    final profile = elevationProfile(_geometry(12345));

    expect(profile.length, lessThanOrEqualTo(elevationProfileMaxPoints + 1));
    expect(profile.length, greaterThan(400));
    expect(profile.first.distanceM, 0);
    // The end of the route survives the thinning.
    expect(
      profile.last.distanceM,
      cumulativeDistancesMeters(_geometry(12345).map((p) => p.pos).toList())
          .last,
    );
  });

  test('downsampling respects a custom limit and keeps the ends', () {
    final samples = List<ElevationSample>.generate(
      1000,
      (i) => ElevationSample(i * 10.0, 100.0 + i),
    );

    final thinned = downsampleElevation(samples, maxPoints: 10);

    expect(thinned.length, lessThanOrEqualTo(11));
    expect(thinned.first, samples.first);
    expect(thinned.last, samples.last);
  });

  test('a nonsensical limit yields a single sample', () {
    final samples = [
      const ElevationSample(0, 100),
      const ElevationSample(10, 110),
    ];
    expect(downsampleElevation(samples, maxPoints: 1), hasLength(1));
    expect(downsampleElevation(const [], maxPoints: 1), isEmpty);
  });
}
