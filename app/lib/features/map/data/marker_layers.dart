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

  /// A marker's disc, wider for the chosen point.
  static List<Object> discRadius() =>
      whenSelected(markerDiscSelectedRadiusPx, markerDiscRadiusPx);

  /// The number inside a disc, which grows with it.
  static List<Object> discTextSize() =>
      whenSelected(discTextSelectedPx, discTextPx);

  /// The name beside a disc.
  static List<Object> nameTextSize() => whenSelected(nameSelectedPx, namePx);

  /// The glyph on a disc: drawn at the size the chosen point wants and
  /// scaled down for the rest, so it keeps its share of whichever disc it
  /// sits on.
  static List<Object> glyphScale() =>
      whenSelected(1.0, markerGlyphUnselectedScale);

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
  );

  /// The glyph on a marker's disc. A feature with no `icon` keeps the plain
  /// disc.
  ml.SymbolLayerProperties glyph() => ml.SymbolLayerProperties(
    iconImage: <Object>['get', 'icon'],
    iconSize: glyphScale(),
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
  ml.SymbolLayerProperties name({required String field}) =>
      ml.SymbolLayerProperties(
        textField: <Object>['get', field],
        textFont: waypointLabelFont,
        textSize: nameTextSize(),
        // On the map, not on a disc: the colour that reads against the
        // style the rider is looking at, outlined in its opposite. The disc
        // under it carries what the point is and whether it is chosen.
        textColor: palette.mapLabel,
        textHaloColor: palette.mapLabelHalo,
        textHaloWidth: 1.2,
        textAnchor: nameAnchor,
        // Ems of the text's own size, so the gap grows with it.
        textOffset: <Object>[0, nameOffsetEm],
        symbolSortKey: whenSelected(0.0, 1.0),
      );
}
