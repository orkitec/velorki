import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/map_drawn.dart';

/// The writes [MapDrawn.describe] names as still under way.
String openWrites() {
  final match = RegExp(r'under way \(([^)]*)\)')
      .firstMatch(MapDrawn.describe());
  return match?.group(1) ?? '';
}

void main() {
  test('a failure names the writes still under way, not those done', () {
    final hung = MapDrawn.writing('setGeoJsonSource velorki-stops');
    final done = MapDrawn.writing('addLayer velorki-route');
    MapDrawn.changed(done);

    expect(MapDrawn.describe(), startsWith('1 write(s) under way'));
    expect(openWrites(), startsWith('setGeoJsonSource velorki-stops '));
    expect(openWrites(), isNot(contains('addLayer')));

    MapDrawn.changed(hung);
    expect(MapDrawn.describe(), startsWith('0 write(s) under way;'));
  });

  test('a job of several writes is named while it runs', () async {
    late String during;
    await MapDrawn.busy('setStops', () async => during = openWrites());

    expect(during, startsWith('setStops '));
    expect(openWrites(), isEmpty);
  });
}
