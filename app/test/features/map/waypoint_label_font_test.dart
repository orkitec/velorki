import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';

void main() {
  group('waypointLabelFont', () {
    // A symbol layer with no `text-font` falls back to the style spec default,
    // `Open Sans Regular, Arial Unicode MS Regular`, which the OpenFreeMap
    // glyph endpoint answers with a 404. MapLibre then never completes the
    // layout of the waypoint source's tiles, so the *circle* layer on the same
    // source disappears along with the labels. Every OpenFreeMap style ships
    // `Noto Sans Regular`.
    test('names a font stack the OpenFreeMap styles serve', () {
      expect(waypointLabelFont, <String>['Noto Sans Regular']);
    });

    test('never falls back to the style spec default', () {
      expect(waypointLabelFont, isNotEmpty);
      expect(waypointLabelFont, isNot(contains('Open Sans Regular')));
      expect(waypointLabelFont, isNot(contains('Arial Unicode MS Regular')));
    });
  });
}
