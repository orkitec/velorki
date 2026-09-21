import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/recording/domain/poi_marks.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A straight track north from 48°N, a fix every 10 m for two kilometres,
/// with the distance of every fix as the analysis would measure it.
final List<TrackPoint> _points = <TrackPoint>[
  for (var i = 0; i <= 200; i++)
    TrackPoint(destinationPoint(const LatLng(48, 11), 0, i * 10.0)),
];
final List<double> _distanceAt = <double>[
  for (var i = 0; i <= 200; i++) i * 10.0,
];

void main() {
  test('a point beside the track is marked at the nearest fix', () {
    // 25 m east of the fix at 1,000 m.
    final poi = RoutePoi(
      pos: destinationPoint(_points[100].pos, 90, 25),
      name: 'Fountain',
      kind: PoiKind.water,
    );
    final marks = poiMarks(<RoutePoi>[poi], _points, _distanceAt);
    expect(marks, hasLength(1));
    expect(marks.single.alongM, closeTo(1000, 1e-6));
    expect(marks.single.poi, same(poi));
  });

  test('a point the ride never came near is dropped', () {
    final far = RoutePoi(
      pos: destinationPoint(_points[100].pos, 90, 500),
      name: 'Far café',
    );
    final justOutside = RoutePoi(
      pos: destinationPoint(_points[50].pos, 90, 61),
      name: 'Just outside',
    );
    final justInside = RoutePoi(
      pos: destinationPoint(_points[50].pos, 270, 59),
      name: 'Just inside',
    );
    final marks = poiMarks(
      <RoutePoi>[far, justOutside, justInside],
      _points,
      _distanceAt,
    );
    expect(marks.map((m) => m.poi.name), <String>['Just inside']);
    expect(marks.single.alongM, closeTo(500, 1e-6));
  });

  test('the marks come back in riding order whatever the route said', () {
    final marks = poiMarks(
      <RoutePoi>[
        RoutePoi(pos: _points[150].pos, name: 'Third'),
        RoutePoi(pos: _points[20].pos, name: 'First'),
        RoutePoi(pos: _points[80].pos, name: 'Second'),
      ],
      _points,
      _distanceAt,
    );
    expect(marks.map((m) => m.poi.name), <String>['First', 'Second', 'Third']);
    expect(marks.map((m) => m.alongM), <double>[200, 800, 1500]);
  });

  test('the reach can be widened', () {
    final poi = RoutePoi(
      pos: destinationPoint(_points[100].pos, 90, 150),
      name: 'Viewpoint',
    );
    expect(poiMarks(<RoutePoi>[poi], _points, _distanceAt), isEmpty);
    expect(
      poiMarks(<RoutePoi>[poi], _points, _distanceAt, withinM: 200),
      hasLength(1),
    );
  });

  test('nothing to match gives nothing', () {
    final poi = RoutePoi(pos: _points[20].pos, name: 'Start');
    expect(poiMarks(const <RoutePoi>[], _points, _distanceAt), isEmpty);
    expect(poiMarks(<RoutePoi>[poi], const <TrackPoint>[], const []), isEmpty);
    // A distance list shorter than the track only covers the fixes it has.
    expect(
      poiMarks(<RoutePoi>[poi], _points, _distanceAt.sublist(0, 5)),
      isEmpty,
    );
  });
}
