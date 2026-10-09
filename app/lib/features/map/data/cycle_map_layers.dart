import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki_cycle_map/velorki_cycle_map.dart'
    show BarrierClass, CycleKind, Side;

import '../domain/cycle_map.dart';

/// The cycle map's colours, as maplibre hex strings, for the day and the
/// night map.
@immutable
class CycleMapColors {
  /// Creates the colours.
  const CycleMapColors({
    required this.infrastructure,
    required this.shared,
    required this.allowed,
    required this.cyclestreet,
    required this.routeNational,
    required this.routeRegional,
    required this.routeLocal,
    required this.unpaved,
    required this.rough,
    required this.barrier,
    required this.barrierCarry,
    required this.outline,
  });

  /// On the day map.
  static const CycleMapColors light = CycleMapColors(
    infrastructure: '#1565C0',
    shared: '#00897B',
    allowed: '#5C7A99',
    cyclestreet: '#90CAF9',
    routeNational: '#6A1B9A',
    routeRegional: '#8E24AA',
    routeLocal: '#BA68C8',
    unpaved: '#A1661A',
    rough: '#C62828',
    barrier: '#37474F',
    barrierCarry: '#C62828',
    outline: '#FFFFFF',
  );

  /// On the night map.
  static const CycleMapColors dark = CycleMapColors(
    infrastructure: '#64B5F6',
    shared: '#4DB6AC',
    allowed: '#90A4AE',
    cyclestreet: '#1E4C7A',
    routeNational: '#CE93D8',
    routeRegional: '#BA68C8',
    routeLocal: '#9C4DB0',
    unpaved: '#D9A441',
    rough: '#EF5350',
    barrier: '#ECEFF1',
    barrierCarry: '#EF5350',
    outline: '#101418',
  );

  /// Cycleways, cycle streets, tracks and lanes.
  final String infrastructure;

  /// Paths shared with walkers.
  final String shared;

  /// Footways bikes may use.
  final String allowed;

  /// The wide band under a cycle street.
  final String cyclestreet;

  /// The halos of the cycle routes, by network.
  final String routeNational;
  final String routeRegional;
  final String routeLocal;

  /// Unpaved ways.
  final String unpaved;

  /// Bumpy ways.
  final String rough;

  /// A barrier, and one the bike has to be carried over.
  final String barrier;
  final String barrierCarry;

  /// The rim round barriers and the contraflow arrows.
  final String outline;

  @override
  bool operator ==(Object other) =>
      other is CycleMapColors &&
      other.infrastructure == infrastructure &&
      other.shared == shared &&
      other.allowed == allowed &&
      other.cyclestreet == cyclestreet &&
      other.routeNational == routeNational &&
      other.routeRegional == routeRegional &&
      other.routeLocal == routeLocal &&
      other.unpaved == unpaved &&
      other.rough == rough &&
      other.barrier == barrier &&
      other.barrierCarry == barrierCarry &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(
    infrastructure,
    shared,
    allowed,
    cyclestreet,
    routeNational,
    routeRegional,
    routeLocal,
    unpaved,
    rough,
    barrier,
    barrierCarry,
    outline,
  );
}

/// One layer of the cycle map.
@immutable
class CycleMapLayer {
  /// Creates the layer.
  const CycleMapLayer({
    required this.name,
    required this.part,
    required this.properties,
    required this.filter,
    this.minZoom = cycleMapMinZoom,
  });

  /// The layer's name within the cycle map; [CycleMapLayers.layerId] makes
  /// it a style id.
  final String name;

  /// The part it draws, which switches it on and off.
  final CycleMapPart part;

  /// How it is drawn.
  final ml.LayerProperties properties;

  /// Which features it draws.
  final List<Object> filter;

  /// The zoom it is drawn from.
  final double minZoom;
}

/// The style layers of the cycle map, bottom to top, all drawing one GeoJSON
/// source of the shape `GeoJsonWriter` writes: lines with `k` (the kind),
/// `t` and `l` (the sides with a track or a lane), `cf`, `nn`/`nr`/`nl`,
/// `u`, `r`; points with `b` (the barrier class).
///
/// Each layer belongs to one [CycleMapPart] and is shown or hidden with it,
/// so a switch in the Layers sheet acts at once. The source is swapped for a
/// new one as the map moves, so layer ids carry the source's generation.
class CycleMapLayers {
  /// The layers in [colors].
  const CycleMapLayers(this.colors);

  /// The colours.
  final CycleMapColors colors;

  /// The style image of the contraflow arrows.
  static const String contraflowImage = 'velorki-cycle-contraflow';

  /// The source of [generation].
  static String sourceId(int generation) => 'velorki-cycle-$generation';

  /// The style id of [layer] drawing the source of [generation].
  static String layerId(int generation, CycleMapLayer layer) =>
      'velorki-cycle-$generation-${layer.name}';

  /// The base style's layers the cycle map goes under, first found first:
  /// the first labels over the roads, so street names stay readable over
  /// the cycle map, and the roads, bridges and buildings stay under it.
  static const List<String> anchors = <String>[
    'waterway_line_label', // OpenFreeMap Liberty, the day map
    'water_name', // OpenFreeMap Fiord, the night map
  ];

  static List<Object> _byZoom(List<double> stops) => <Object>[
    'interpolate',
    <Object>['linear'],
    <Object>['zoom'],
    for (var i = 0; i + 1 < stops.length; i += 2) ...[stops[i], stops[i + 1]],
  ];

  /// How far a track or a lane is drawn beside the middle of its road:
  /// on it zoomed out, where the road is a hairline, beside it close in.
  static List<Object> _sideOffset(double sign) =>
      _byZoom(<double>[13, 0, 15, 2 * sign, 16, 4 * sign, 18, 10 * sign]);

  static List<Object> _kind(CycleKind kind) => <Object>[
    '==',
    <Object>['get', 'k'],
    kind.index,
  ];

  static List<Object> _hasSide(String key, int side) => <Object>[
    'any',
    <Object>[
      '==',
      <Object>['get', key],
      side,
    ],
    <Object>[
      '==',
      <Object>['get', key],
      Side.both,
    ],
  ];

  static List<Object> _has(String key) => <Object>['has', key];

  ml.LineLayerProperties _line({
    required String color,
    required List<double> width,
    List<double>? dashes,
    Object? offset,
    double opacity = 1,
    String cap = 'butt',
  }) => ml.LineLayerProperties(
    lineColor: color,
    lineWidth: _byZoom(width),
    lineOpacity: opacity,
    lineDasharray: dashes,
    lineOffset: offset ?? 0,
    lineCap: cap,
    lineJoin: 'round',
  );

  /// Every layer, bottom to top.
  List<CycleMapLayer> get layers => <CycleMapLayer>[
    // Wider and stronger the farther a route reaches: in a city most
    // streets are on a local route, which must not drown the lanes.
    for (final (name, part, key, color, width, opacity)
        in <(String, CycleMapPart, String, String, List<double>, double)>[
          (
            'route-national',
            CycleMapPart.routesNational,
            'nn',
            colors.routeNational,
            <double>[13, 6, 16, 10, 18, 16],
            0.4,
          ),
          (
            'route-regional',
            CycleMapPart.routesRegional,
            'nr',
            colors.routeRegional,
            <double>[13, 5, 16, 8, 18, 13],
            0.32,
          ),
          (
            'route-local',
            CycleMapPart.routesLocal,
            'nl',
            colors.routeLocal,
            <double>[13, 4, 16, 6, 18, 10],
            0.2,
          ),
        ])
      CycleMapLayer(
        name: name,
        part: part,
        filter: _has(key),
        properties: _line(
          color: color,
          width: width,
          opacity: opacity,
          cap: 'round',
        ),
      ),
    CycleMapLayer(
      name: 'cyclestreet-band',
      part: CycleMapPart.infrastructure,
      filter: _kind(CycleKind.cyclestreet),
      properties: _line(
        color: colors.cyclestreet,
        width: <double>[13, 4, 16, 9, 18, 18],
        opacity: 0.7,
        cap: 'round',
      ),
    ),
    CycleMapLayer(
      name: 'unpaved',
      part: CycleMapPart.surface,
      filter: _has('u'),
      properties: _line(
        color: colors.unpaved,
        width: <double>[13, 1.5, 16, 2.5, 18, 4],
        dashes: <double>[2, 2],
      ),
    ),
    CycleMapLayer(
      name: 'allowed',
      part: CycleMapPart.paths,
      filter: _kind(CycleKind.allowed),
      properties: _line(
        color: colors.allowed,
        width: <double>[13, 1.2, 16, 2, 18, 3],
        dashes: <double>[0.1, 2],
        cap: 'round',
      ),
    ),
    CycleMapLayer(
      name: 'shared',
      part: CycleMapPart.paths,
      filter: _kind(CycleKind.shared),
      properties: _line(
        color: colors.shared,
        width: <double>[13, 1.5, 16, 2.5, 18, 4],
        dashes: <double>[3, 1.5],
      ),
    ),
    CycleMapLayer(
      name: 'cycleway',
      part: CycleMapPart.infrastructure,
      filter: _kind(CycleKind.cycleway),
      properties: _line(
        color: colors.infrastructure,
        width: <double>[13, 1.5, 16, 2.8, 18, 4.5],
        cap: 'round',
      ),
    ),
    CycleMapLayer(
      name: 'cyclestreet',
      part: CycleMapPart.infrastructure,
      filter: _kind(CycleKind.cyclestreet),
      properties: _line(
        color: colors.infrastructure,
        width: <double>[13, 1, 16, 2, 18, 3],
        cap: 'round',
      ),
    ),
    for (final (side, sign, key) in <(int, double, String)>[
      (Side.left, -1, 'left'),
      (Side.right, 1, 'right'),
    ]) ...[
      CycleMapLayer(
        name: 'track-$key',
        part: CycleMapPart.infrastructure,
        filter: _hasSide('t', side),
        properties: _line(
          color: colors.infrastructure,
          width: <double>[13, 1.2, 16, 2.4, 18, 3.5],
          offset: _sideOffset(sign),
        ),
      ),
      CycleMapLayer(
        name: 'lane-$key',
        part: CycleMapPart.infrastructure,
        filter: _hasSide('l', side),
        properties: _line(
          color: colors.infrastructure,
          width: <double>[13, 1.2, 16, 2.4, 18, 3.5],
          dashes: <double>[2, 1.2],
          offset: _sideOffset(sign),
        ),
      ),
    ],
    CycleMapLayer(
      name: 'rough',
      part: CycleMapPart.surface,
      filter: _has('r'),
      properties: _line(
        color: colors.rough,
        width: <double>[13, 3, 16, 5, 18, 8],
        dashes: <double>[0.25, 2.5],
      ),
    ),
    CycleMapLayer(
      name: 'contraflow',
      part: CycleMapPart.contraflow,
      filter: _has('cf'),
      minZoom: 15,
      properties: const ml.SymbolLayerProperties(
        symbolPlacement: 'line',
        symbolSpacing: 140,
        iconImage: contraflowImage,
        iconSize: <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          15,
          0.6,
          18,
          0.9,
        ],
        iconRotationAlignment: 'map',
        iconAllowOverlap: false,
        iconIgnorePlacement: true,
      ),
    ),
    CycleMapLayer(
      name: 'barriers',
      part: CycleMapPart.barriers,
      filter: _has('b'),
      minZoom: 15,
      properties: ml.CircleLayerProperties(
        circleColor: <Object>[
          'case',
          <Object>[
            '==',
            <Object>['get', 'b'],
            BarrierClass.carry,
          ],
          colors.barrierCarry,
          colors.barrier,
        ],
        circleRadius: _byZoom(<double>[15, 2.5, 18, 5]),
        circleStrokeColor: colors.outline,
        circleStrokeWidth: 1.2,
      ),
    ),
  ];
}
