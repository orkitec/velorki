import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki_cycle_map/velorki_cycle_map.dart'
    show BarrierClass, CycleKind, Direction, RoadClass, Side, TrafficClass;

import '../domain/cycle_map.dart';

/// The cycle map's colours, as maplibre hex strings, for the day and the
/// night map.
@immutable
class CycleMapColors {
  /// Creates the colours.
  const CycleMapColors({
    required this.infrastructure,
    required this.sharedLane,
    required this.shared,
    required this.allowed,
    required this.cyclestreet,
    required this.routeNational,
    required this.routeRegional,
    required this.routeLocal,
    required this.routeMtb,
    required this.unpaved,
    required this.rugged,
    required this.rough,
    required this.steps,
    required this.mtbEasy,
    required this.mtbMedium,
    required this.mtbHard,
    required this.limit30,
    required this.limit20,
    required this.walk,
    required this.noMotor,
    required this.noBikes,
    required this.barrier,
    required this.barrierCarry,
    required this.trafficArrow,
    required this.outline,
  });

  /// On the day map.
  static const CycleMapColors light = CycleMapColors(
    infrastructure: '#1565C0',
    sharedLane: '#5C8FD6',
    shared: '#00897B',
    allowed: '#5C7A99',
    cyclestreet: '#90CAF9',
    routeNational: '#6A1B9A',
    routeRegional: '#8E24AA',
    routeLocal: '#BA68C8',
    routeMtb: '#E65100',
    unpaved: '#A1661A',
    rugged: '#6D4C41',
    rough: '#C62828',
    steps: '#795548',
    mtbEasy: '#1E88E5',
    mtbMedium: '#E53935',
    mtbHard: '#212121',
    limit30: '#26C6DA',
    limit20: '#66BB6A',
    walk: '#AED581',
    noMotor: '#00C853',
    noBikes: '#9E9E9E',
    barrier: '#37474F',
    barrierCarry: '#C62828',
    trafficArrow: '#9E9E9E',
    outline: '#FFFFFF',
  );

  /// On the night map.
  static const CycleMapColors dark = CycleMapColors(
    infrastructure: '#64B5F6',
    sharedLane: '#90CAF9',
    shared: '#4DB6AC',
    allowed: '#90A4AE',
    cyclestreet: '#1E4C7A',
    routeNational: '#CE93D8',
    routeRegional: '#BA68C8',
    routeLocal: '#9C4DB0',
    routeMtb: '#FFB74D',
    unpaved: '#D9A441',
    rugged: '#BCAAA4',
    rough: '#EF5350',
    steps: '#BCAAA4',
    mtbEasy: '#64B5F6',
    mtbMedium: '#EF5350',
    mtbHard: '#FAFAFA',
    limit30: '#4DD0E1',
    limit20: '#81C784',
    walk: '#C5E1A5',
    noMotor: '#69F0AE',
    noBikes: '#757575',
    barrier: '#ECEFF1',
    barrierCarry: '#EF5350',
    trafficArrow: '#9E9E9E',
    outline: '#101418',
  );

  /// Cycleways, cycle streets, tracks and lanes.
  final String infrastructure;

  /// Lanes bikes share: bus lanes, lanes marked with bike symbols only,
  /// shoulders and sidewalks bikes may use.
  final String sharedLane;

  /// Paths shared with walkers.
  final String shared;

  /// Footways bikes may use.
  final String allowed;

  /// The wide band under a cycle street.
  final String cyclestreet;

  /// The halos of the cycle routes, by network, and of mountain-bike
  /// routes.
  final String routeNational;
  final String routeRegional;
  final String routeLocal;
  final String routeMtb;

  /// Gravel, rugged and bumpy ways.
  final String unpaved;
  final String rugged;
  final String rough;

  /// Steps.
  final String steps;

  /// Mountain-bike difficulty: S0-S1, S2, S3 and harder.
  final String mtbEasy;
  final String mtbMedium;
  final String mtbHard;

  /// The band under a road by how calm it is.
  final String limit30;
  final String limit20;
  final String walk;
  final String noMotor;
  final String noBikes;

  /// A barrier, and one the bike has to be carried over.
  final String barrier;
  final String barrierCarry;

  /// The arrow of the cars' way on a contraflow street.
  final String trafficArrow;

  /// The rim round barriers and arrows.
  final String outline;

  List<String> get _all => <String>[
    infrastructure,
    sharedLane,
    shared,
    allowed,
    cyclestreet,
    routeNational,
    routeRegional,
    routeLocal,
    routeMtb,
    unpaved,
    rugged,
    rough,
    steps,
    mtbEasy,
    mtbMedium,
    mtbHard,
    limit30,
    limit20,
    walk,
    noMotor,
    noBikes,
    barrier,
    barrierCarry,
    trafficArrow,
    outline,
  ];

  @override
  bool operator ==(Object other) =>
      other is CycleMapColors && listEquals(other._all, _all);

  @override
  int get hashCode => Object.hashAll(_all);
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
/// `t`, `l` and `s` (the sides with a track, a lane or a shared lane), `rc`
/// (the road's size), `o`, `dl`, `dr` (directions), `cf`, `nn`/`nr`/`nl`,
/// `mr`, `u`, `rg`, `r`, `m`, `rp`, `tr`; points with `b`.
///
/// Each layer belongs to one [CycleMapPart] and is shown or hidden with it,
/// so a switch in the Layers sheet acts at once. The source is swapped for a
/// new one as the map moves, so layer ids carry the source's generation.
class CycleMapLayers {
  /// The layers in [colors].
  const CycleMapLayers(this.colors);

  /// The colours.
  final CycleMapColors colors;

  /// The style images the layers draw: the chevron on a line ridden one
  /// way (a cycleway, or a track or lane beside a road), in the line's own
  /// colour, wider than the line so its shape shows; and the two chevrons
  /// of a contraflow street (the traffic's way, and the bikes' against
  /// it).
  static const String arrowImage = 'velorki-cycle-arrow';
  static const String onewayStreetImage = 'velorki-cycle-oneway-street';
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

  /// How far from the middle of a road its side lines run, by zoom and the
  /// road's size ([RoadClass] minor, middle, major), in pixels: half the
  /// base map's road and half a cycle line, so a lane sits on the road's
  /// edge. Zoomed out, where the road is a hairline, the lines lie on it.
  static const List<(double, double, double, double)> _sideOffsets = [
    (13, 0, 0, 0),
    (14, 1, 1.2, 1.5),
    (15, 3, 3.7, 4.5),
    (16, 4, 4.5, 5.5),
    (18, 6.5, 6.5, 7.5),
    (20, 12, 12, 14),
  ];

  /// The size of the side arrows, against their bitmap.
  static const double _sideArrowSize = 1.0;

  static List<Object> _byZoom(List<double> stops) => <Object>[
    'interpolate',
    <Object>['linear'],
    <Object>['zoom'],
    for (var i = 0; i + 1 < stops.length; i += 2) ...[stops[i], stops[i + 1]],
  ];

  static List<Object> _get(String key) => <Object>['get', key];

  static List<Object> _is(String key, int value) => <Object>[
    '==',
    _get(key),
    value,
  ];

  static List<Object> _kind(CycleKind kind) => _is('k', kind.index);

  static List<Object> _has(String key) => <Object>['has', key];

  static List<Object> _any(List<Object> conditions) => <Object>[
    'any',
    ...conditions,
  ];

  static List<Object> _all(List<Object> conditions) => <Object>[
    'all',
    ...conditions,
  ];

  static List<Object> _onSide(String key, int side) =>
      _any(<Object>[_is(key, side), _is(key, Side.both)]);

  static String _dirKey(int side) => side == Side.left ? 'dl' : 'dr';

  /// [value] for a road of each size.
  static List<Object> _byRoad(double minor, double middle, double major) =>
      <Object>[
        'match',
        _get('rc'),
        RoadClass.major,
        major,
        RoadClass.middle,
        middle,
        minor,
      ];

  static List<Object> _sideOffset(double sign) => <Object>[
    'interpolate',
    <Object>['linear'],
    <Object>['zoom'],
    for (final (zoom, minor, middle, major) in _sideOffsets) ...[
      zoom,
      _byRoad(minor * sign, middle * sign, major * sign),
    ],
  ];

  /// The width by zoom, half again as wide where [twoWay] holds: a
  /// two-way line is wider than a one-way one, which says its direction
  /// zoomed out, where no arrow shows.
  static List<Object> _width(List<double> stops, List<Object> twoWay) =>
      <Object>[
        'interpolate',
        <Object>['linear'],
        <Object>['zoom'],
        for (var i = 0; i + 1 < stops.length; i += 2) ...[
          stops[i],
          <Object>['case', twoWay, stops[i + 1] * 1.5, stops[i + 1]],
        ],
      ];

  ml.LineLayerProperties _line({
    required Object color,
    required Object width,
    List<double>? dashes,
    Object? offset,
    double opacity = 1,
    String cap = 'butt',
  }) => ml.LineLayerProperties(
    lineColor: color,
    lineWidth: width is List<double> ? _byZoom(width) : width,
    lineOpacity: opacity,
    lineDasharray: dashes,
    lineOffset: offset ?? 0,
    lineCap: cap,
    lineJoin: 'round',
  );

  static ml.SymbolLayerProperties _arrows({
    required String image,
    required Object size,
    required double spacing,
    Object? offset,
  }) => ml.SymbolLayerProperties(
    symbolPlacement: 'line',
    symbolSpacing: spacing,
    iconImage: image,
    iconSize: size,
    // Against the way's own direction an arrow turns round.
    iconRotate: <Object>['case', _is('o', Direction.backward), 180, 0],
    iconOffset: offset,
    iconRotationAlignment: 'map',
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
  );

  /// The arrows of one side's track, lane or shared lane, beside the road.
  CycleMapLayer _sideArrows(int side) {
    final key = _dirKey(side);
    final sign = side == Side.left ? -1.0 : 1.0;
    // The offset turns with the arrow, so a turned one moves to the other
    // side unless its offset turns too.
    List<Object> at(double px) {
      final v = px * sign / _sideArrowSize;
      return <Object>[
        'case',
        _is(key, Direction.backward),
        <Object>[
          'literal',
          <double>[0, -v],
        ],
        <Object>[
          'literal',
          <double>[0, v],
        ],
      ];
    }

    return CycleMapLayer(
      name: 'side-arrows-${side == Side.left ? 'left' : 'right'}',
      part: CycleMapPart.directions,
      minZoom: 15.5,
      filter: _any(<Object>[
        _is(key, Direction.forward),
        _is(key, Direction.backward),
      ]),
      properties: ml.SymbolLayerProperties(
        symbolPlacement: 'line',
        symbolSpacing: 70,
        iconImage: arrowImage,
        iconSize: _sideArrowSize,
        iconRotate: <Object>['case', _is(key, Direction.backward), 180, 0],
        iconOffset: <Object>[
          'interpolate',
          <Object>['linear'],
          <Object>['zoom'],
          for (final (zoom, minor, middle, major) in _sideOffsets)
            if (zoom >= 15) ...[
              zoom,
              <Object>[
                'match',
                _get('rc'),
                RoadClass.major,
                at(major),
                RoadClass.middle,
                at(middle),
                at(minor),
              ],
            ],
        ],
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
    );
  }

  /// The lines beside the road on [side]: tracks, lanes, shared lanes.
  List<CycleMapLayer> _sideLines(int side) {
    final name = side == Side.left ? 'left' : 'right';
    final sign = side == Side.left ? -1.0 : 1.0;
    final twoWay = _is(_dirKey(side), Direction.both);
    const width = <double>[13, 1.2, 16, 2.4, 18, 3.5];
    return <CycleMapLayer>[
      CycleMapLayer(
        name: 'shared-lane-$name',
        part: CycleMapPart.infrastructure,
        filter: _onSide('s', side),
        properties: _line(
          color: colors.sharedLane,
          width: _width(width, twoWay),
          dashes: <double>[1.5, 3],
          offset: _sideOffset(sign),
        ),
      ),
      CycleMapLayer(
        name: 'track-$name',
        part: CycleMapPart.infrastructure,
        filter: _onSide('t', side),
        properties: _line(
          color: colors.infrastructure,
          width: _width(width, twoWay),
          offset: _sideOffset(sign),
        ),
      ),
      CycleMapLayer(
        name: 'lane-$name',
        part: CycleMapPart.infrastructure,
        filter: _onSide('l', side),
        properties: _line(
          color: colors.infrastructure,
          width: _width(width, twoWay),
          dashes: <double>[2, 1.2],
          offset: _sideOffset(sign),
        ),
      ),
    ];
  }

  /// How long a layer takes to fade in as the map zooms in, in zoom steps:
  /// from a step before its own zoom it comes up, and zooming out it goes
  /// the same way, rather than vanishing at once.
  static const double fadeZooms = 1;

  /// Every layer, bottom to top, each fading in over [fadeZooms] before its
  /// zoom.
  List<CycleMapLayer> get layers => [for (final l in _layers) _faded(l)];

  static CycleMapLayer _faded(CycleMapLayer layer) {
    final from = layer.minZoom - fadeZooms;
    Object fade(Object? opacity) => <Object>[
      'interpolate',
      <Object>['linear'],
      <Object>['zoom'],
      from,
      0,
      layer.minZoom,
      opacity ?? 1,
    ];
    final p = layer.properties;
    final faded = switch (p) {
      ml.LineLayerProperties() => p.copyWith(
        ml.LineLayerProperties(lineOpacity: fade(p.lineOpacity)),
      ),
      ml.SymbolLayerProperties() => p.copyWith(
        ml.SymbolLayerProperties(iconOpacity: fade(p.iconOpacity)),
      ),
      ml.CircleLayerProperties() => p.copyWith(
        ml.CircleLayerProperties(
          circleOpacity: fade(p.circleOpacity),
          circleStrokeOpacity: fade(p.circleStrokeOpacity),
        ),
      ),
      _ => p,
    };
    return CycleMapLayer(
      name: layer.name,
      part: layer.part,
      properties: faded,
      filter: layer.filter,
      minZoom: from,
    );
  }

  List<CycleMapLayer> get _layers => <CycleMapLayer>[
    // How calm a road is, as a band under everything else.
    CycleMapLayer(
      name: 'traffic',
      part: CycleMapPart.traffic,
      filter: _has('tr'),
      properties: _line(
        color: <Object>[
          'match',
          _get('tr'),
          TrafficClass.limit30,
          colors.limit30,
          TrafficClass.limit20,
          colors.limit20,
          TrafficClass.walk,
          colors.walk,
          TrafficClass.noMotor,
          colors.noMotor,
          colors.noBikes,
        ],
        width: <double>[13, 3, 16, 8, 18, 16],
        opacity: 0.4,
        cap: 'round',
      ),
    ),
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
          (
            'route-mtb',
            CycleMapPart.mtb,
            'mr',
            colors.routeMtb,
            <double>[13, 4, 16, 7, 18, 12],
            0.3,
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
      filter: _all(<Object>[
        _has('u'),
        <Object>['!', _has('rg')],
      ]),
      properties: _line(
        color: colors.unpaved,
        width: <double>[13, 1.5, 16, 2.5, 18, 4],
        dashes: <double>[2, 2],
      ),
    ),
    CycleMapLayer(
      name: 'rugged',
      part: CycleMapPart.surface,
      filter: _has('rg'),
      properties: _line(
        color: colors.rugged,
        width: <double>[13, 2, 16, 3.5, 18, 5],
        dashes: <double>[1, 1.2],
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
        width: _width(
          <double>[13, 1.5, 16, 2.5, 18, 4],
          <Object>['!', _has('o')],
        ),
        dashes: <double>[3, 1.5],
      ),
    ),
    CycleMapLayer(
      name: 'steps',
      part: CycleMapPart.barriers,
      minZoom: 15,
      filter: _kind(CycleKind.steps),
      properties: _line(
        color: colors.steps,
        width: <double>[15, 3, 16, 4, 18, 7],
        dashes: <double>[0.4, 0.4],
      ),
    ),
    CycleMapLayer(
      name: 'steps-ramp',
      part: CycleMapPart.barriers,
      minZoom: 16,
      filter: _has('rp'),
      properties: _line(
        color: colors.infrastructure,
        width: <double>[16, 1.5, 18, 2.5],
        offset: _byZoom(<double>[16, 3, 18, 5]),
      ),
    ),
    CycleMapLayer(
      name: 'cycleway',
      part: CycleMapPart.infrastructure,
      filter: _kind(CycleKind.cycleway),
      properties: _line(
        color: colors.infrastructure,
        width: _width(
          <double>[13, 1.5, 16, 2.8, 18, 4.5],
          <Object>['!', _has('o')],
        ),
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
    ..._sideLines(Side.left),
    ..._sideLines(Side.right),
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
      name: 'mtb-scale',
      part: CycleMapPart.mtb,
      minZoom: 14,
      filter: _has('m'),
      properties: _line(
        color: <Object>[
          'step',
          _get('m'),
          colors.mtbEasy,
          2,
          colors.mtbMedium,
          3,
          colors.mtbHard,
        ],
        width: <double>[14, 4, 16, 6, 18, 9],
        dashes: <double>[0.2, 2],
      ),
    ),
    CycleMapLayer(
      name: 'oneway-arrows',
      part: CycleMapPart.directions,
      minZoom: 15,
      filter: _all(<Object>[
        _has('o'),
        _any(<Object>[
          _kind(CycleKind.cycleway),
          _kind(CycleKind.shared),
          _kind(CycleKind.allowed),
        ]),
      ]),
      properties: _arrows(
        image: arrowImage,
        size: _byZoom(<double>[15, 0.8, 16, 1.0, 18, 1.3]),
        spacing: 60,
      ),
    ),
    _sideArrows(Side.left),
    _sideArrows(Side.right),
    // A street one-way for bikes as well: a grey chevron in its middle,
    // the way the traffic goes, so a rider sees not to ride against it.
    // Not where a lane or track beside it shows its own direction: its
    // chevrons say it already.
    CycleMapLayer(
      name: 'oneway-streets',
      part: CycleMapPart.onewayStreets,
      minZoom: 15,
      filter: _all(<Object>[
        _has('o'),
        <Object>['!', _has('cf')],
        <Object>['!', _has('dl')],
        <Object>['!', _has('dr')],
        _any(<Object>[_kind(CycleKind.none), _kind(CycleKind.cyclestreet)]),
      ]),
      properties: _arrows(
        image: onewayStreetImage,
        size: _byZoom(<double>[15, 0.8, 16, 1.0, 18, 1.3]),
        spacing: 90,
      ),
    ),
    CycleMapLayer(
      name: 'contraflow',
      part: CycleMapPart.contraflow,
      filter: _has('cf'),
      minZoom: 15,
      properties: _arrows(
        image: contraflowImage,
        size: _byZoom(<double>[15, 0.9, 16, 1.1, 18, 1.4]),
        spacing: 100,
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
          _is('b', BarrierClass.carry),
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
