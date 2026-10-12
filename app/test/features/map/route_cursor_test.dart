import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/route_cursor.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Three kilometres due north.
final List<LatLng> _line = <LatLng>[
  for (var m = 0; m <= 3000; m += 1000)
    destinationPoint(const LatLng(48, 11), 0, m.toDouble()),
];

void main() {
  test('puts the dot as far along the line as the finger is', () {
    final map = FakeMapController();
    final cursor = RouteCursor()
      ..map = map
      ..setLine(_line, () => _line);

    cursor.show(1500);
    expect(haversineMeters(map.routeCursor!, _line.first), closeTo(1500, 1));
    cursor.show(2750);
    expect(haversineMeters(map.routeCursor!, _line.first), closeTo(2750, 1));

    // The same place again is not drawn again.
    final calls = map.routeCursorCalls.length;
    cursor.show(2750);
    expect(map.routeCursorCalls, hasLength(calls));
    cursor.dispose();
  });

  test('a lifted finger leaves the dot for a moment, a new touch keeps it', () {
    fakeAsync((async) {
      final map = FakeMapController();
      final cursor = RouteCursor()
        ..map = map
        ..setLine(_line, () => _line);

      cursor.show(1000);
      cursor.show(null);
      async.elapse(routeCursorLinger ~/ 2);
      expect(map.routeCursor, isNotNull);

      // Back on the chart before it went: it stays, and moves.
      cursor.show(2000);
      async.elapse(routeCursorLinger);
      expect(haversineMeters(map.routeCursor!, _line.first), closeTo(2000, 1));

      cursor.show(null);
      async.elapse(routeCursorLinger);
      expect(map.routeCursor, isNull);
      expect(map.routeCursorCalls.last, isNull);
      cursor.dispose();
    });
  });

  test('another line, another map or the end takes the dot away at once', () {
    final map = FakeMapController();
    final other = FakeMapController();
    final cursor = RouteCursor()
      ..map = map
      ..setLine(_line, () => _line);

    cursor.show(1000);
    cursor.setLine(_line.reversed, () => _line.reversed.toList());
    expect(map.routeCursor, isNull);

    cursor.show(1000);
    cursor.map = other;
    expect(map.routeCursor, isNull);
    cursor.show(500);
    expect(other.routeCursor, isNotNull);

    cursor.dispose();
    expect(other.routeCursor, isNull);
  });

  test('without a line there is no dot', () {
    final map = FakeMapController();
    final cursor = RouteCursor()
      ..map = map
      ..setLine(null, () => _line);
    cursor.show(1000);
    expect(map.routeCursorCalls, isEmpty);
    cursor.dispose();
  });
}
