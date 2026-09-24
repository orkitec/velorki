import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/marker_glyph.dart';
import 'package:velorki/features/map/data/marker_layers.dart';
import 'package:velorki/features/map/data/maplibre_map_controller.dart';

const MapPalette _palette = MapPalette(
  routeMain: '#111111',
  routeMainCasing: '#222222',
  routeAlternative: '#333333',
  routeAlternatives: <String>['#333333'],
  routePreview: '#444444',
  track: '#555555',
  trackSlow: '#505050',
  trackFast: '#5F5F5F',
  waypointStart: '#666666',
  waypointVia: '#777777',
  waypointEnd: '#888888',
  waypointStroke: '#999999',
  waypointLabel: '#AAAAAA',
  waypointLabelHalo: '#BBBBBB',
  mapLabel: '#ABABAB',
  mapLabelHalo: '#BCBCBC',
  positionDot: '#CCCCCC',
  positionAccuracy: '#DDDDDD',
);

void main() {
  const markers = MarkerLayers(_palette);

  test('a point on the route and a place beside it are written the same '
      'way: above the disc, never on it', () {
    final onRoute = markers.name(field: 'label').toJson();
    final beside = markers.name(field: 'name').toJson();

    for (final property in <String>[
      'text-anchor',
      'text-offset',
      'text-size',
      'text-color',
      'text-halo-color',
      'text-halo-width',
      'text-font',
      'symbol-sort-key',
    ]) {
      expect(
        onRoute[property],
        beside[property],
        reason: '$property differs between the two sources',
      );
    }
    // Only which property of the feature holds the name differs.
    expect(onRoute['text-field'], <Object>['get', 'label']);
    expect(beside['text-field'], <Object>['get', 'name']);

    // Above the point, by enough to clear the disc under it at either size.
    expect(onRoute['text-anchor'], 'bottom');
    expect(MarkerLayers.nameOffsetEm, lessThan(0));
    expect(
      MarkerLayers.namePx * -MarkerLayers.nameOffsetEm,
      greaterThan(markerDiscRadiusPx + 2),
    );
    expect(
      MarkerLayers.nameSelectedPx * -MarkerLayers.nameOffsetEm,
      greaterThan(markerDiscSelectedRadiusPx + 2),
    );
  });

  test('the number stays inside the disc and is never dropped', () {
    final number = markers.number().toJson();

    expect(number['text-anchor'], 'center');
    expect(number['text-allow-overlap'], isTrue);
    expect(number['text-ignore-placement'], isTrue);
    expect(number['text-field'], <Object>['get', 'disc']);
    // A name may be dropped when two points sit on top of one another; the
    // chosen one sorts first so it is the one that survives.
    expect(markers.name(field: 'label').toJson()['text-allow-overlap'], isNull);
  });

  test('everything a choice changes is one question about the feature', () {
    const chosen = <Object>['get', 'selected'];
    final disc = markers.disc(color: '#123456', strokeWidth: 2).toJson();

    expect(disc['circle-radius'], <Object>[
      'case',
      chosen,
      markerDiscSelectedRadiusPx,
      markerDiscRadiusPx,
    ]);
    expect(disc['circle-color'], <Object>[
      'case',
      chosen,
      '#444444',
      '#123456',
    ]);
    // The glyph is there in both states, only smaller in one of them.
    final glyph = markers.glyph().toJson();
    expect(glyph['icon-image'], <Object>['get', 'icon']);
    expect(glyph['icon-size'], <Object>[
      'case',
      chosen,
      1.0,
      markerGlyphUnselectedScale,
    ]);
    expect(markers.name(field: 'name').toJson()['text-size'], <Object>[
      'case',
      chosen,
      MarkerLayers.nameSelectedPx,
      MarkerLayers.namePx,
    ]);
  });
}
