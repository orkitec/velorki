import 'package:test/test.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  final points = <TrackPoint>[
    TrackPoint(const LatLng(48.0, 11.0), time: DateTime.utc(2026, 9, 24)),
    TrackPoint(
      const LatLng(48.01, 11.0),
      time: DateTime.utc(2026, 9, 24, 0, 5),
    ),
  ];

  test('a course keeps its sub-sport', () {
    for (final subSport in [
      FitSubSport.road,
      FitSubSport.mountain,
      FitSubSport.gravelCycling,
      FitSubSport.generic,
    ]) {
      final course = FitCodec.decodeCourse(
        FitCodec.encodeCourse(points, name: 'Ride', subSport: subSport),
      );
      expect(course.subSport, subSport);
      expect(course.sport, FitSport.cycling);
    }
  });

  test('an activity says its sub-sport in the session', () {
    final activity = FitCodec.decodeActivityFile(
      FitCodec.encodeActivity(
        points,
        name: 'Ride',
        subSport: FitSubSport.eBikeMountain,
      ),
    );
    expect(activity.session!.subSport, FitSubSport.eBikeMountain);
  });

  test('an unknown sub-sport reads as none', () {
    expect(FitSubSport.fromFitValue(3), isNull);
    expect(FitSubSport.fromFitValue(46), FitSubSport.gravelCycling);
  });
}
