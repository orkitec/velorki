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
  test('puts the badge as far along the line as the cursor stands', () {
    final map = FakeMapController();
    final cursor = RouteCursor()
      ..map = map
      ..setLine(_line, () => _line);

    cursor.value = 1500;
    expect(haversineMeters(map.routeCursor!, _line.first), closeTo(1500, 1));
    cursor.value = 2750;
    expect(haversineMeters(map.routeCursor!, _line.first), closeTo(2750, 1));

    // The same place again is not drawn again.
    final calls = map.routeCursorCalls.length;
    cursor.value = 2750;
    expect(map.routeCursorCalls, hasLength(calls));
    cursor.dispose();
  });

  test('the badge stays until the cursor is hidden', () {
    fakeAsync((async) {
      final map = FakeMapController();
      final cursor = RouteCursor()
        ..map = map
        ..setLine(_line, () => _line);

      cursor.value = 1000;
      async.elapse(const Duration(minutes: 1));
      expect(map.routeCursor, isNotNull);

      cursor.clear();
      expect(cursor.value, isNull);
      expect(map.routeCursor, isNull);
      expect(map.routeCursorCalls.last, isNull);
      cursor.dispose();
    });
  });

  test('another line hides the cursor; another map takes the badge with '
      'it; the end takes it away', () {
    final map = FakeMapController();
    final other = FakeMapController();
    final cursor = RouteCursor()
      ..map = map
      ..setLine(_line, () => _line);
    var told = 0;
    cursor.addListener(() => told++);

    cursor.value = 1000;
    cursor.setLine(_line.reversed, () => _line.reversed.toList());
    expect(cursor.value, isNull);
    expect(told, 2, reason: 'the charts hear of both');
    expect(map.routeCursor, isNull);

    cursor.value = 1000;
    cursor.map = other;
    expect(map.routeCursor, isNull);
    expect(haversineMeters(other.routeCursor!, _line.last), closeTo(1000, 1));

    // Without a map the cursor still moves, and the badge is back where it
    // is once a map is.
    cursor.map = null;
    expect(other.routeCursor, isNull);
    cursor.value = 500;
    cursor.map = map;
    expect(haversineMeters(map.routeCursor!, _line.last), closeTo(500, 1));

    cursor.dispose();
    expect(map.routeCursor, isNull);
  });

  test('without a line there is no badge', () {
    final map = FakeMapController();
    final cursor = RouteCursor()
      ..map = map
      ..setLine(null, () => _line);
    cursor.value = 1000;
    expect(map.routeCursorCalls, isEmpty);
    cursor.dispose();
  });
}
