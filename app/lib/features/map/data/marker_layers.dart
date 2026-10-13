import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'marker_glyph.dart';
import 'maplibre_map_controller.dart' show MapPalette, waypointLabelFont;

/// How a point is drawn on the map, in one place.
///
/// Points come to the style through two sources — the ones the route is
/// routed through and the places beside it — and they are drawn the same
/// way: a disc, the kind's glyph on it, and the name above. Keeping the
/// geometry and the layout here rather than spelling it out per source is
/// what stops the two drifting apart, which is how the planner ended up
/// writing a name across a marker while the library wrote it above one.
///
/// Everything a point's state changes is a `case` on one feature property,
/// `selected`, so the style answers it per feature and nothing has to be
/// drawn twice.
class MarkerLayers {
  /// Builds the layers in [palette]'s colours.
  const MarkerLayers(this.palette);

  /// The colours of the map the markers are drawn on.
  final MapPalette palette;

  /// The number inside a disc, in logical pixels, and the chosen point's.
  static const double discTextPx = 12;
  static const double discTextSelectedPx = 14;

  /// The name beside a disc, and the chosen point's, which is larger: that
  /// is how a rider finds the point again after tapping a line of a list.
  static const double namePx = 12;
  static const double nameSelectedPx = 15;

  /// How far above its point a name sits, in ems of its own size, so the
  /// gap grows with the text and clears the disc at both sizes.
  ///
  /// At 12 px that is 16.8 px against a disc of 12 plus a 2 px rim, and at
  /// 15 px it is 21 px against 15 plus 2.
  static const double nameOffsetEm = -1.4;

  /// Where a name sits relative to its point: above it, never on it.
  static const String nameAnchor = 'bottom';

  /// `true` for the chosen point, `false` for every other: the one question
  /// the marker styles ask of a feature.
  ///
  /// Every feature writes the property, so this is never `null`, which a
  /// `case` could not answer.
  static List<Object> whenSelected(Object chosen, Object rest) => <Object>[
    'case',
    <Object>['get', 'selected'],
    chosen,
    rest,
  ];

  /// How opaque a point the rider has already ridden past is drawn: there,
  /// so the route still reads, but plainly behind them.
  static const double passedOpacity = 0.35;

  /// The opacity of a marker: faded when the feature says it is `passed`.
  /// A feature without the property (a place beside the route) is never
  /// passed.
  static List<Object> opacity() => <Object>[
    'case',
    <Object>[
      'coalesce',
      <Object>['get', 'passed'],
      false,
    ],
    passedOpacity,
    1.0,
  ];

  /// A marker's disc, wider for the chosen point.
  static List<Object> discRadius() =>
      whenSelected(markerDiscSelectedRadiusPx, markerDiscRadiusPx);

  /// The number inside a disc, which grows with it.
  static List<Object> discTextSize() =>
      whenSelected(discTextSelectedPx, discTextPx);

  /// The name beside a disc.
  static List<Object> nameTextSize() => whenSelected(nameSelectedPx, namePx);

  /// The glyph on a disc, as the name of its picture: the feature's `icon`
  /// for the chosen point, the smaller picture of the same glyph
  /// ([markerGlyphUnselectedName]) for the rest, so it keeps its share of
  /// whichever disc it sits on.
  ///
  /// Two pictures, each drawn at the size it is shown at, rather than one
  /// scaled by `icon-size`: MapLibre filters a scaled icon, and that blurs
  /// a glyph's thin strokes. Unscaled, a picture registered at the screen's
  /// pixel ratio is drawn pixel for pixel.
  ///
  /// A feature with no `icon` names no picture.
  static List<Object> glyphImage() => <Object>[
    'case',
    <Object>['has', 'icon'],
    whenSelected(
      <Object>['get', 'icon'],
      <Object>[
        'concat',
        <Object>['get', 'icon'],
        markerGlyphUnselectedSuffix,
      ],
    ),
    '',
  ];

  /// How much smaller a stop's glyph is than the chosen point's: smaller
  /// than a route's own places, which matter more than any tap nearby.
  static const double stopGlyphScale = 0.62;

  /// A stop's disc, and the chosen stop's, which is as wide as any chosen
  /// point's.
  static final double stopDiscRadiusPx = markerDiscRadiusFor(
    markerGlyphOnDiscSizePx * stopGlyphScale,
  );
  static final double stopDiscSelectedRadiusPx = markerDiscSelectedRadiusPx;

  /// The rim round a stop's disc and round a bubble of stops.
  static const double stopStrokePx = 1.5;

  /// What a stop's picture is called in the style: one per colour it is
  /// drawn in — its kind's, or `selected` for the chosen stop — and glyph,
  /// [glyphName] being the stop's `icon` property, `null` for none.
  ///
  /// [stopImage] asks each feature for the same name.
  static String stopImageName(String state, String? glyphName) =>
      'velorki-stop-$state-${glyphName ?? 'none'}';

  /// The picture of a single stop, disc and glyph in one, named from the
  /// feature's `selected`, `kind` and `icon` as [stopImageName] names it.
  static List<Object> stopImage() => <Object>[
    'concat',
    'velorki-stop-',
    whenSelected('selected', <Object>['get', 'kind']),
    '-',
    <Object>[
      'coalesce',
      <Object>['get', 'icon'],
      'none',
    ],
  ];

  /// A single stop: its disc with its glyph on it, as one symbol so it
  /// fades in and out with the map's placement rather than popping.
  ///
  /// Forced, never placed: every stop shows, however close the next.
  ml.SymbolLayerProperties stop() => ml.SymbolLayerProperties(
    iconImage: stopImage(),
    iconOpacity: opacity(),
    iconAnchor: 'center',
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
  );

  /// Whether a feature of a clustered source is a bubble standing for
  /// several points, and the opposite: the stop layers draw the single
  /// stops, the cluster layers the bubbles.
  static const List<Object> isCluster = <Object>['has', 'point_count'];
  static const List<Object> isNotCluster = <Object>['!', isCluster];

  /// The radius of the bubble of a cluster, stepping up with how many stops
  /// it holds: under [clusterRadiusSteps]' first count, under its second,
  /// and beyond.
  static const List<double> clusterRadiiPx = <double>[14, 17, 20];
  static const List<int> clusterRadiusSteps = <int>[10, 50];

  /// What the picture of a bubble of [radiusPx] is called in the style.
  ///
  /// One picture per radius, each drawn at its own size with the stops'
  /// rim round it, rather than one scaled by `icon-size`, which MapLibre
  /// filters and so blurs.
  static String clusterImageName(double radiusPx) =>
      'velorki-stop-cluster-${radiusPx.round()}';

  /// The picture of a cluster bubble, stepping up with how many stops it
  /// holds.
  static List<Object> clusterImage() => <Object>[
    'step',
    <Object>['get', 'point_count'],
    clusterImageName(clusterRadiiPx[0]),
    clusterRadiusSteps[0],
    clusterImageName(clusterRadiiPx[1]),
    clusterRadiusSteps[1],
    clusterImageName(clusterRadiiPx[2]),
  ];

  /// What a cluster bubble says: how many stops it holds, "99+" beyond.
  static List<Object> clusterCount() => <Object>[
    'case',
    <Object>[
      '>',
      <Object>['get', 'point_count'],
      99,
    ],
    '99+',
    <Object>[
      'to-string',
      <Object>['get', 'point_count'],
    ],
  ];

  /// The bubble of a cluster of stops, in the accent with the stop discs'
  /// rim, and the count on it: one symbol, so it fades in and out with the
  /// map's placement and crossfades as the clusters change with the zoom.
  /// Forced, like a waypoint's number: every bubble shows, and its count is
  /// inside it, where nothing else is.
  ml.SymbolLayerProperties clusterBubble() => ml.SymbolLayerProperties(
    iconImage: clusterImage(),
    iconAnchor: 'center',
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
    textField: clusterCount(),
    textFont: waypointLabelFont,
    textSize: discTextPx,
    textColor: palette.stopClusterLabel,
    textAllowOverlap: true,
    textIgnorePlacement: true,
    textAnchor: 'center',
  );

  /// How much smaller the glyph on a group's bubble is than the chosen
  /// point's: a little larger than a single stop's ([stopGlyphScale]), so a
  /// bubble reads as more than one stop of its kind.
  static const double groupGlyphScale = 0.75;

  /// The disc of a group's bubble, the glyph of its kind on it.
  static final double groupDiscRadiusPx = markerDiscRadiusFor(
    markerGlyphOnDiscSizePx * groupGlyphScale,
  );

  /// The count on a group's bubble: its text size and the pill under it,
  /// as wide as a count of one, two and three characters ("99+") needs.
  static const double groupCountPx = 9;
  static const double groupBadgeHeightPx = 12;
  static const List<double> groupBadgeWidthsPx = <double>[12, 15, 20];

  /// The counts at which a group's bubble takes its next wider pill.
  static const List<int> groupBadgeSteps = <int>[10, 100];

  /// Where the middle of the count's pill sits on a group's bubble: over
  /// its upper right shoulder.
  static Offset get groupBadgeCentre =>
      Offset(groupDiscRadiusPx * 0.8, -groupDiscRadiusPx * 0.8);

  /// The pill for a count of [characters] (1–3), relative to the middle of
  /// the bubble's disc.
  static Rect groupBadge(int characters) => Rect.fromCenter(
    center: groupBadgeCentre,
    width: groupBadgeWidthsPx[(characters - 1).clamp(0, 2)],
    height: groupBadgeHeightPx,
  );

  /// How far, in logical pixels, a group's bubbles stand off the middle of
  /// the stops they gather, each group in its own direction round a
  /// circle: the bubbles of different groups gathered at much the same
  /// place fan out instead of covering one another.
  static const double groupFanRadiusPx = 16;

  /// The offset of the bubbles of the group at [index] of [count]: none
  /// for a lone group, else a step round the circle from straight up,
  /// clockwise as the screen reads.
  static Offset groupFanOffset(int index, int count) {
    if (count < 2) return Offset.zero;
    final angle = -math.pi / 2 + index * 2 * math.pi / count;
    // Rounded to a tenth of a pixel: the same offset every time.
    double tenth(double v) => (v * 10).roundToDouble() / 10;
    return Offset(
      tenth(math.cos(angle) * groupFanRadiusPx),
      tenth(math.sin(angle) * groupFanRadiusPx),
    );
  }

  /// What the picture of a bubble of [group] with a count of [characters]
  /// is called in the style.
  static String groupImageName(String group, int characters) =>
      'velorki-stop-group-$group-$characters';

  /// The picture of a bubble of [group], its pill as wide as its count.
  static List<Object> groupImage(String group) => <Object>[
    'step',
    <Object>['get', 'point_count'],
    groupImageName(group, 1),
    groupBadgeSteps[0],
    groupImageName(group, 2),
    groupBadgeSteps[1],
    groupImageName(group, 3),
  ];

  /// The bubble of a group of stops of one kind: the kind's disc and glyph,
  /// a little larger than a single stop's, with the count on a pill over
  /// its shoulder, stood off by [offset] ([groupFanOffset]).
  ///
  /// Forced, like the stops: every bubble shows wherever the others are,
  /// so none goes missing behind another group's and nothing is placed
  /// anew as the map pans.
  ml.SymbolLayerProperties groupBubble(String group, Offset offset) {
    final count = offset + groupBadgeCentre;
    return ml.SymbolLayerProperties(
      iconImage: groupImage(group),
      iconAnchor: 'center',
      iconOffset: <Object>[offset.dx, offset.dy],
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
      textField: clusterCount(),
      textFont: waypointLabelFont,
      textSize: groupCountPx,
      textColor: palette.stopClusterLabel,
      // Ems of the count's own size.
      textOffset: <Object>[count.dx / groupCountPx, count.dy / groupCountPx],
      textAllowOverlap: true,
      textIgnorePlacement: true,
      textAnchor: 'center',
    );
  }

  /// The disc itself. [color] is the colour of what the point is; the
  /// chosen point takes the chosen colour instead.
  ml.CircleLayerProperties disc({
    required Object color,
    required double strokeWidth,
  }) => ml.CircleLayerProperties(
    circleRadius: discRadius(),
    circleColor: whenSelected(palette.routePreview, color),
    circleStrokeWidth: strokeWidth,
    circleStrokeColor: palette.waypointStroke,
    circleOpacity: opacity(),
    circleStrokeOpacity: opacity(),
  );

  /// The glyph on a marker's disc. A feature with no `icon` keeps the plain
  /// disc.
  ml.SymbolLayerProperties glyph() => ml.SymbolLayerProperties(
    iconImage: glyphImage(),
    iconOpacity: opacity(),
    iconAnchor: 'center',
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
  );

  /// The number inside a marker's disc, for a point that carries no glyph.
  ///
  /// Forced rather than placed: a point's number is the one thing that must
  /// never be dropped, and it is inside the disc, where nothing else is.
  ml.SymbolLayerProperties number() => ml.SymbolLayerProperties(
    textField: <Object>['get', 'disc'],
    textFont: waypointLabelFont,
    textSize: discTextSize(),
    textColor: palette.waypointLabel,
    textHaloColor: palette.waypointLabelHalo,
    textHaloWidth: 0.6,
    textOpacity: opacity(),
    textAllowOverlap: true,
    textIgnorePlacement: true,
    textAnchor: 'center',
  );

  /// The name above a marker's disc, reading [field] of the feature.
  ///
  /// The two sources name the property differently for their own reasons;
  /// everything about how the text is laid out comes from here, so a point
  /// on the route and a place beside it are written the same way on every
  /// screen.
  ///
  /// Placed rather than forced: a plan with points on top of one another is
  /// better read with a name missing than with two over each other. The
  /// chosen point sorts first, so its name is the one that survives.
  ///
  /// [chosenOnly] writes the name of the chosen point alone: the stops are
  /// many and mostly unnamed, and a name for each would bury the map.
  ml.SymbolLayerProperties name({
    required String field,
    bool chosenOnly = false,
  }) => ml.SymbolLayerProperties(
    textField: chosenOnly
        ? whenSelected(<Object>['get', field], '')
        : <Object>['get', field],
    textFont: waypointLabelFont,
    textSize: nameTextSize(),
    // On the map, not on a disc: the colour that reads against the
    // style the rider is looking at, outlined in its opposite. The disc
    // under it carries what the point is and whether it is chosen.
    textColor: palette.mapLabel,
    textHaloColor: palette.mapLabelHalo,
    textHaloWidth: 1.2,
    textOpacity: opacity(),
    textAnchor: nameAnchor,
    // Ems of the text's own size, so the gap grows with it.
    textOffset: <Object>[0, nameOffsetEm],
    symbolSortKey: whenSelected(0.0, 1.0),
  );
}
