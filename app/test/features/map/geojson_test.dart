import 'dart:math' as math;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/geojson.dart';
import 'package:velorki/features/map/data/marker_glyph.dart';
import 'package:velorki/features/map/data/tile_template.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki_geo/velorki_geo.dart';

List<dynamic> _features(Map<String, dynamic> collection) =>
    collection['features'] as List<dynamic>;

Map<String, dynamic> _first(Map<String, dynamic> collection) =>
    _features(collection).first as Map<String, dynamic>;

void main() {
  test('a marker that stands for something carries its glyph in the '
      'feature, and a plain one carries none', () {
    const icon = Icons.water_drop_outlined;
    final pois = poisFeatureCollection(const [
      MapPoi(
        position: LatLng(48, 11),
        name: 'Tap',
        kind: MapPoiKind.water,
        icon: icon,
      ),
      MapPoi(position: LatLng(48, 11.1), name: 'X', kind: MapPoiKind.generic),
    ]);
    final features = pois['features']! as List<dynamic>;
    final first = (features[0] as Map<String, dynamic>)['properties']!;
    expect((first as Map<String, dynamic>)['icon'], markerGlyphName(icon));
    expect(markerGlyphName(icon), 'velorki-glyph-${icon.codePoint}');
    final second = (features[1] as Map<String, dynamic>)['properties']!;
    expect((second as Map<String, dynamic>).containsKey('icon'), isFalse);

    final waypoints = waypointsFeatureCollection(const [
      MapWaypoint(
        position: LatLng(48, 11),
        kind: MapWaypointKind.start,
        icon: icon,
      ),
    ]);
    final wp =
        ((waypoints['features']! as List<dynamic>).single
                as Map<String, dynamic>)['properties']!
            as Map<String, dynamic>;
    // On the route or beside it, a point wears the same glyph on its own
    // disc; nothing sits next to a disc any more.
    expect(wp['icon'], markerGlyphName(icon));
  });

  group('what a point on the route is drawn with', () {
    const icon = Icons.terrain_outlined;

    Map<String, dynamic> drawn({
      String? name,
      IconData? withIcon,
      bool selected = false,
    }) {
      final collection = waypointsFeatureCollection([
        MapWaypoint(
          position: const LatLng(48, 11),
          kind: MapWaypointKind.via,
          label: name,
          icon: withIcon,
          selected: selected,
        ),
        // A second point, so the one under test is number 2 and a number
        // left over from the index cannot pass for a name.
        const MapWaypoint(
          position: LatLng(48.1, 11),
          kind: MapWaypointKind.end,
        ),
      ]);
      return ((collection['features']! as List<dynamic>).first
              as Map<String, dynamic>)['properties']!
          as Map<String, dynamic>;
    }

    // The four points a plan can hold, chosen and not: the disc says one
    // thing, the label the other, and the number is written exactly once.
    final cases = <String, (Map<String, dynamic>, String, String, bool)>{
      'a kind and a name': (
        drawn(name: 'Pico', withIcon: icon),
        '',
        '(1) Pico',
        true,
      ),
      'a kind, no name': (drawn(withIcon: icon), '', '1', true),
      'no kind, a name': (drawn(name: 'Home'), '1', 'Home', false),
      'no kind, no name': (drawn(), '1', '', false),
      'a kind and a name, chosen': (
        drawn(name: 'Pico', withIcon: icon, selected: true),
        '',
        '(1) Pico',
        true,
      ),
      'a kind, no name, chosen': (
        drawn(withIcon: icon, selected: true),
        '',
        '1',
        true,
      ),
      'no kind, a name, chosen': (
        drawn(name: 'Home', selected: true),
        '1',
        'Home',
        false,
      ),
      'no kind, no name, chosen': (drawn(selected: true), '1', '', false),
    };

    cases.forEach((what, expected) {
      final (props, disc, label, hasIcon) = expected;
      test('$what: one disc, one label, and the icon in every state', () {
        expect(props['disc'], disc, reason: 'disc of $what');
        expect(props['label'], label, reason: 'label of $what');
        // The number is written once: on the disc, or in the label, never
        // both and never neither.
        final onDisc = disc == '1';
        final inLabel = label.startsWith('(1)') || label == '1';
        expect(onDisc ^ inLabel, isTrue, reason: 'the number of $what');
        // A point that stands for something keeps its icon whatever else
        // is true of it.
        expect(props.containsKey('icon'), hasIcon, reason: 'the icon of $what');
        if (hasIcon) expect(props['icon'], markerGlyphName(icon));
      });
    });

    test('a place beside the route keeps its icon and its one name when it '
        'is the chosen one', () {
      final chosen = poisFeatureCollection(const [
        MapPoi(
          position: LatLng(48, 11),
          name: 'Tap',
          kind: MapPoiKind.water,
          icon: icon,
          selected: true,
        ),
      ]);
      final poi =
          ((chosen['features']! as List<dynamic>).single
                  as Map<String, dynamic>)['properties']!
              as Map<String, dynamic>;
      expect(poi['selected'], isTrue);
      expect(poi['icon'], markerGlyphName(icon));
      expect(poi['name'], 'Tap');
    });
  });

  group('lineFeatureCollection', () {
    test('writes lon/lat pairs in GeoJSON order', () {
      final json = lineFeatureCollection(const [
        LatLng(47.1, 8.5),
        LatLng(47.2, 8.6),
      ]);

      expect(json['type'], 'FeatureCollection');
      final geometry = _first(json)['geometry'] as Map<String, dynamic>;
      expect(geometry['type'], 'LineString');
      expect(geometry['coordinates'], [
        [8.5, 47.1],
        [8.6, 47.2],
      ]);
    });

    test('carries the properties through', () {
      final json = lineFeatureCollection(
        const [LatLng(0, 0), LatLng(1, 1)],
        properties: const {'style': 'main'},
      );

      expect(_first(json)['properties'], {'style': 'main'});
    });

    test('yields an empty collection for a degenerate line', () {
      // A one point LineString is invalid GeoJSON; MapLibre would drop the
      // whole source rather than just the feature.
      expect(_features(lineFeatureCollection(const [])), isEmpty);
      expect(_features(lineFeatureCollection(const [LatLng(1, 2)])), isEmpty);
    });
  });

  group('waypointsFeatureCollection', () {
    const waypoints = [
      MapWaypoint(position: LatLng(47.0, 8.0), kind: MapWaypointKind.start),
      MapWaypoint(position: LatLng(47.5, 8.5), kind: MapWaypointKind.via),
      MapWaypoint(
        position: LatLng(48.0, 9.0),
        kind: MapWaypointKind.end,
        label: 'Zoo',
      ),
    ];

    test('numbers the waypoints from one on their discs; a named one wears '
        'its name beside it', () {
      final features = _features(waypointsFeatureCollection(waypoints))
          .cast<Map<String, dynamic>>();

      // No kind on any of these, so the disc keeps the number and the label
      // says only the name.
      expect(features.map((f) => (f['properties'] as Map)['disc']), [
        '1',
        '2',
        '3',
      ]);
      expect(features.map((f) => (f['properties'] as Map)['label']), [
        '',
        '',
        'Zoo',
      ]);
      expect(features.map((f) => (f['properties'] as Map)['kind']), [
        'start',
        'via',
        'end',
      ]);
    });

    test('marks every feature draggable and round-trips the index', () {
      final features = _features(waypointsFeatureCollection(waypoints))
          .cast<Map<String, dynamic>>();

      for (var i = 0; i < features.length; i++) {
        expect((features[i]['properties'] as Map)['draggable'], isTrue);
        expect(features[i]['id'], waypointFeatureId(i));
        expect(waypointIndexFromFeatureId(features[i]['id'] as String), i);
      }
    });

    test('a screen that reads a route writes its markers static', () {
      final features = _features(
        waypointsFeatureCollection(waypoints, draggable: false),
      ).cast<Map<String, dynamic>>();
      for (final f in features) {
        expect((f['properties'] as Map)['draggable'], isFalse);
      }
    });

    test('a point keeps the number it has in the route, and says whether '
        'the rider has passed it', () {
      final features = _features(
        waypointsFeatureCollection(const [
          MapWaypoint(
            position: LatLng(47.0, 8.0),
            kind: MapWaypointKind.start,
            passed: true,
            number: 1,
          ),
          MapWaypoint(
            position: LatLng(47.5, 8.5),
            kind: MapWaypointKind.via,
            number: 3,
          ),
          MapWaypoint(
            position: LatLng(48.0, 9.0),
            kind: MapWaypointKind.end,
            icon: Icons.flag,
            number: 5,
          ),
        ]),
      ).cast<Map<String, dynamic>>();
      final props = features.map((f) => f['properties'] as Map).toList();
      expect(props.map((p) => p['disc']), ['1', '3', '']);
      expect(props.last['label'], '5');
      expect(props.map((p) => p['passed']), [true, false, false]);
    });

    test('ignores feature ids that are not waypoints', () {
      expect(waypointIndexFromFeatureId(null), isNull);
      expect(waypointIndexFromFeatureId('velorki-position'), isNull);
      expect(waypointIndexFromFeatureId('velorki-wp-x'), isNull);
    });

    test('is empty for no waypoints', () {
      expect(_features(waypointsFeatureCollection(const [])), isEmpty);
    });
  });

  group('positionFeatureCollection', () {
    test('omits accuracy and heading when they are unknown', () {
      final json = positionFeatureCollection(const LatLng(47.0, 8.0));

      expect(_first(json)['properties'], isEmpty);
      expect(_first(json)['geometry'], {
        'type': 'Point',
        'coordinates': [8.0, 47.0],
      });
    });

    test('carries accuracy and the course while moving', () {
      final json = positionFeatureCollection(
        const LatLng(47.0, 8.0),
        accuracyM: 12.5,
        headingDeg: 90,
        speedMps: 4,
      );

      expect(_first(json)['properties'], {'accuracy': 12.5, 'heading': 90.0});
    });

    test('omits the course while standing still', () {
      final json = positionFeatureCollection(
        const LatLng(47.0, 8.0),
        accuracyM: 12.5,
        headingDeg: 90,
        speedMps: 0.2,
      );

      expect(_first(json)['properties'], {'accuracy': 12.5});
    });

    test('omits the course when no speed came with it', () {
      final json = positionFeatureCollection(
        const LatLng(47.0, 8.0),
        headingDeg: 90,
      );

      expect(_first(json)['properties'], isEmpty);
    });

    test('is empty without a fix', () {
      expect(_features(positionFeatureCollection(null)), isEmpty);
    });
  });

  group('puckHeading', () {
    test('needs a course, a speed, and enough of it', () {
      expect(puckHeading(null, 5), isNull);
      expect(puckHeading(90, null), isNull);
      expect(puckHeading(double.nan, 5), isNull);
      expect(puckHeading(double.infinity, 5), isNull);
      expect(puckHeading(90, double.nan), isNull);
      expect(puckHeading(90, minHeadingSpeedMps - 0.01), isNull);
      expect(puckHeading(90, minHeadingSpeedMps), 90);
    });

    test('normalises the course into a full turn', () {
      expect(puckHeading(370, 5), 10);
      expect(puckHeading(-90, 5), 270);
      expect(puckHeading(360, 5), 0);
    });
  });

  group('accuracyRingRadiusExpression', () {
    test('is an exponential zoom interpolation with base 2', () {
      final expression = accuracyRingRadiusExpression(50, 0);

      expect(expression[0], 'interpolate');
      expect(expression[1], ['exponential', 2]);
      expect(expression[2], ['zoom']);
      expect(expression[3], 0);
    });

    test('matches the metres-per-pixel ratio at both stops', () {
      const accuracy = 40.0;
      const latitude = 47.0;
      final expression = accuracyRingRadiusExpression(accuracy, latitude);

      final atZoom0 = expression[4] as double;
      final atZoom22 = expression[6] as double;

      expect(atZoom0, closeTo(accuracy / metersPerPixel(0, latitude), 1e-9));
      expect(atZoom22, closeTo(accuracy / metersPerPixel(22, latitude), 1e-6));
      // Exponential base 2 between the stops means one doubling per zoom.
      expect(atZoom22 / atZoom0, closeTo(math.pow(2, 22).toDouble(), 1e-3));
    });

    test('shrinks the pixel radius towards the poles', () {
      expect(
        accuracyRingRadiusExpression(50, 60)[4] as double,
        greaterThan(accuracyRingRadiusExpression(50, 0)[4] as double),
      );
    });
  });

  group('expandTileTemplate', () {
    test('expands {s} into one URL per subdomain', () {
      expect(
        expandTileTemplate(
          'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
        ),
        [
          'https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
          'https://b.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
          'https://c.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
        ],
      );
    });

    test('leaves a template without {s} alone', () {
      expect(expandTileTemplate('https://tiles/{z}/{x}/{y}.png'), [
        'https://tiles/{z}/{x}/{y}.png',
      ]);
    });

    test('is empty for an unconfigured overlay', () {
      expect(expandTileTemplate(''), isEmpty);
      expect(
        expandTileTemplate('https://{s}.x/{z}.png', subdomains: const []),
        isEmpty,
      );
    });
  });
}
