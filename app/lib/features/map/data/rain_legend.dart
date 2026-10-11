import 'package:flutter/foundation.dart';

import '../domain/weather_map.dart';

// The soft rain reads each pixel of a rain image against its service's own
// legend: a pixel in one of the legend's colours (within
// [rainLegendTolerance], drawn at least [rainLegendMinAlpha] opaque) is rain
// of that colour's class; the service's "no data" colour is no data; any
// other pixel (the DWD's line around its radars' reach, the edges the
// service smooths, labels) is nothing at all. A class's alpha rises with its
// rank in the legend, from [rainAlphaLightest] for the lightest rain to
// [rainAlphaHeaviest] for the heaviest; the top quarter of the classes
// ([rainHeavyRank]) is never made fainter by the softening of edges.

/// How far, per channel, a pixel's colour may lie from a legend colour and
/// still be read as it.
const int rainLegendTolerance = 12;

/// How far, per channel, a pixel of a legend whose unknown colours are the
/// heaviest ([RainLegend.unmatchedIsHeaviest]) may lie from its colours and
/// still be read as the nearest: a colour the service mixed from two of its
/// own when it resampled the image. Further off, it is a colour of its own.
const int rainLegendLooseTolerance = 40;

/// How opaque a pixel has to be to count as rain: the services draw their
/// rain fully opaque, and what is less is a line's or an edge's smoothing.
const int rainLegendMinAlpha = 200;

/// The alpha of the lightest class of rain.
const double rainAlphaLightest = 0.6;

/// The alpha of the heaviest class.
const double rainAlphaHeaviest = 0.95;

/// The rank (0 the lightest class, 1 the heaviest) from which rain counts
/// as heavy: the top quarter of the classes.
const double rainHeavyRank = 0.75;

/// The alpha from which a pixel counts as heavy rain.
const double rainAlphaHeavy =
    rainAlphaLightest + (rainAlphaHeaviest - rainAlphaLightest) * rainHeavyRank;

/// What a pixel that is no rain at all is read as ([RainLegend.classify]).
const int rainNone = -1;

/// What a pixel in the service's "no data" colour is read as.
const int rainNoData = -2;

/// A rain service's legend: its colours (0xRRGGBB), each the class it
/// stands for, lightest first.
@immutable
class RainLegend {
  /// A legend of [classes], lightest first, each the colours drawn for it.
  RainLegend(
    List<List<int>> classes, {
    this.noData,
    this.drawnIn,
    this.unmatchedIsHeaviest = false,
  }) : colours = <int>[for (final c in classes) ...c],
       classOf = <int>[
         for (var i = 0; i < classes.length; i++)
           for (final _ in classes[i]) i,
       ],
       classCount = classes.length + (unmatchedIsHeaviest ? 1 : 0);

  /// A legend whose colours each stand for the class of [drawnIn] at the
  /// same index of [classOf], and are drawn in its colours.
  RainLegend.recoloured(
    this.colours,
    this.classOf, {
    required RainLegend this.drawnIn,
    this.noData,
  }) : unmatchedIsHeaviest = false,
       classCount = drawnIn.classCount;

  /// The legend's colours, lightest first.
  final List<int> colours;

  /// The class each of [colours] stands for.
  final List<int> classOf;

  /// How many classes there are, the lightest 0.
  final int classCount;

  /// The colour the service draws where it has no data; `null` for none.
  final int? noData;

  /// The legend whose classes [classOf] names and whose colours the rain
  /// is drawn in; `null` where it is drawn in its own.
  final RainLegend? drawnIn;

  /// Whether an opaque pixel the legend does not hold is the heaviest
  /// class, one above the legend's own: for a service that draws nothing
  /// but its data and whose colours for the heaviest rain are not known.
  /// One near a colour of the legend ([rainLegendLooseTolerance]) is read
  /// as that colour's class instead.
  final bool unmatchedIsHeaviest;

  /// The class of the pixel (r, g, b, a), 0 the lightest; [rainNoData] in
  /// the [noData] colour, [rainNone] for anything else.
  int classify(int r, int g, int b, int a) {
    if (a == 0) return rainNone;
    if (isNoData(r, g, b, a)) return rainNoData;
    if (a < rainLegendMinAlpha) return rainNone;
    final best = _nearest(r, g, b, rainLegendTolerance);
    if (best >= 0) return classOf[best];
    if (!unmatchedIsHeaviest) return rainNone;
    final loose = _nearest(r, g, b, rainLegendLooseTolerance);
    return loose >= 0 ? classOf[loose] : classCount - 1;
  }

  /// Whether the pixel (r, g, b, a) is the service's "no data".
  bool isNoData(int r, int g, int b, int a) {
    final noData = this.noData;
    return a > 0 && noData != null && _near(noData, r, g, b);
  }

  /// The index of the colour nearest to (r, g, b) within [tolerance] per
  /// channel; -1 for none.
  int _nearest(int r, int g, int b, int tolerance) {
    var best = -1;
    var bestDistance = 1 << 30;
    for (var i = 0; i < colours.length; i++) {
      final c = colours[i];
      final dr = (c >> 16 & 0xFF) - r;
      final dg = (c >> 8 & 0xFF) - g;
      final db = (c & 0xFF) - b;
      if (dr.abs() > tolerance ||
          dg.abs() > tolerance ||
          db.abs() > tolerance) {
        continue;
      }
      final d = dr * dr + dg * dg + db * db;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// The alpha class [k] is drawn at, by its rank.
  double alphaOf(int k) => classCount <= 1
      ? rainAlphaHeaviest
      : rainAlphaLightest +
            (rainAlphaHeaviest - rainAlphaLightest) * k / (classCount - 1);

  /// The colour (0xRRGGBB) the pixel (r, g, b) of class [k] is drawn in:
  /// its own, or where the legend is recoloured, [drawnIn]'s for the class.
  int colourOf(int k, int r, int g, int b) {
    final into = drawnIn;
    if (into != null) return into.colours[into.classOf.indexOf(k)];
    return r << 16 | g << 8 | b;
  }

  static bool _near(int c, int r, int g, int b) =>
      ((c >> 16 & 0xFF) - r).abs() <= rainLegendTolerance &&
      ((c >> 8 & 0xFF) - g).abs() <= rainLegendTolerance &&
      ((c & 0xFF) - b).abs() <= rainLegendTolerance;
}

/// The legend [palette] names.
RainLegend rainLegendOf(RainPalette palette) => switch (palette) {
  RainPalette.dwd => dwdRadarLegend,
  RainPalette.noaa => noaaRadarLegend,
  RainPalette.hsaf => hsafLegend,
  RainPalette.dwdModel6h => dwdModel6hLegend,
};

/// The DWD radar's legend (`dwd:Niederschlagsradar`), the same for its
/// nowcast and for ICON-EU asked for in the style `niederschlagsradar`:
/// `https://maps.dwd.de/geoserver/dwd/wms?service=WMS&version=1.3.0&request=GetLegendGraphic&layer=dwd:Niederschlagsradar&format=application/json`
/// (and `&layer=dwd:Icon-eu_reg00625_fd_sl_TOTPREC01H&style=niederschlagsradar`),
/// read 2026-10-11. Classes in mm an hour; "no data" `#7D7D7D` at 30 %,
/// "dry" `#FFFFFF` fully transparent. In its images the rain is these
/// colours fully opaque, "no data" `#7E7E7E` at alpha 77, and the line
/// around the radars' reach (`#FB00FF`, `#C03DC2`, smoothed) no class.
final RainLegend dwdRadarLegend = RainLegend(const <List<int>>[
  <int>[0x33FFFF], // [0.1, 0.2)
  <int>[0x1ACC9A], // [0.2, 0.4)
  <int>[0x019934], // [0.4, 1)
  <int>[0x4DB31B], // [1, 2)
  <int>[0x99CC01], // [2, 3)
  <int>[0xCCE601], // [3, 5)
  <int>[0xFFFF01], // [5, 7.5)
  <int>[0xFFC401], // [7.5, 10)
  <int>[0xFF8901], // [10, 15)
  <int>[0xFF4501], // [15, 30)
  <int>[0xFE0000], // [30, 45)
  <int>[0xE5004C], // [45, 75)
  <int>[0xCC0098], // [75, 100)
  <int>[0x6600CB], // [100, 150)
  <int>[0x0000FE], // 150 and more
], noData: 0x7D7D7D);

/// The H SAF rain's legend (`mtg_fd:h40b`):
/// `https://view.eumetsat.int/geoserver/ows?service=WMS&version=1.3.0&request=GetLegendGraphic&layer=mtg_fd:h40b&format=application/json`,
/// read 2026-10-11. Classes in mm an hour, up to the upper bound named;
/// under 0.001 transparent.
final RainLegend hsafLegend = RainLegend(const <List<int>>[
  <int>[0xCCFFCC], // < 2
  <int>[0x99E699], // < 4
  <int>[0x66CC66], // < 7
  <int>[0x33B333], // < 10
  <int>[0x3399CC], // < 15
  <int>[0x3366FF], // < 20
  <int>[0x0000FF], // < 25
  <int>[0x6600CC], // < 30
  <int>[0x9933CC], // < 40
  <int>[0xCC0099], // < 50
  <int>[0x800080], // 50 and more
]);

/// The global ICON's six-hour legend (`dwd:Icon_reg025_fd_sl_TOTPREC06H`):
/// `https://maps.dwd.de/geoserver/dwd/wms?service=WMS&version=1.3.0&request=GetLegendGraphic&layer=dwd:Icon_reg025_fd_sl_TOTPREC06H&format=application/json`,
/// read 2026-10-11; "under 0.1 mm" is a black veil at alpha 20, no class.
/// Each class is drawn as the DWD radar's class for its mean rate an hour
/// (the class's middle over six hours), so the forecast reads like the
/// radar: 0.1–0.5 mm in six hours is the radar's lightest, 200–300 mm its
/// 30–45 mm an hour.
final RainLegend dwdModel6hLegend = RainLegend.recoloured(
  const <int>[
    0xDCF7C3, // 0.1–0.5 mm
    0xB9F77C, // 0.5–1
    0x00E601, // 1–2
    0x00BF01, // 2–5
    0x008017, // 5–10
    0x33B9FF, // 10–15
    0x007DFF, // 15–20
    0xFFC040, // 20–25
    0xE69900, // 25–30
    0xB37700, // 30–35
    0xFF0000, // 35–40
    0xCC0000, // 40–50
    0xA60000, // 50–60
    0xFE00FF, // 60–70
    0xD800D9, // 70–80
    0xBC00BF, // 80–90
    0xA500A6, // 90–100
    0xC7B3FF, // 100–150
    0xAA8CFF, // 150–200
    0x8E66FF, // 200–300
    0xFFFFFF, // more than 300
  ],
  const <int>[0, 0, 1, 2, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 8, 9, 9, 9, 10, 11],
  drawnIn: dwdRadarLegend,
);

/// NOAA's base reflectivity (`radar/radar_base_reflectivity_time`). The
/// service publishes no colour legend (`…/ImageServer/legend?f=json` names
/// only its RGB bands, `?f=json` has no colour map): these are the colours
/// of its `exportImage` with `interpolation=RSP_NearestNeighbor`, read from
/// frames over the US on 2026-10-11, in order along the ramp. Ten colours a
/// class, which by where the ramp's yellow (40 dBZ) and red (50 dBZ) fall
/// is 5 dBZ; the lightest class all the grey-blue below 5 dBZ. The heaviest
/// colours were not seen (nothing above about 55 dBZ fell that day), so an
/// opaque colour not among them counts as the heaviest class: the service
/// draws nothing but its data; one near the ramp, as the service's own
/// resampling mixes them, is the class of the nearest.
final RainLegend noaaRadarLegend = RainLegend(const <List<int>>[
  <int>[
    0xBABFB4, 0xB3B9B4, 0xB0B6B4, 0xADB3B4, 0xAAB1B4, 0xA8AEB4, 0xA5ABB4, //
    0xA2A9B5, 0x9FA6B5, 0x9CA3B5, 0x9AA0B5, 0x979EB5, 0x949BB5, 0x8F97B4,
    0x8A94B2, 0x8590B1, 0x808CB0, 0x7C89AF, 0x7785AD, 0x7281AC, 0x6D7DAB,
    0x687AA9, 0x6376A8,
  ], // below 5 dBZ
  <int>[
    0x6074A7, 0x5D71A6, 0x596FA5, 0x566CA4, 0x536AA4, 0x5068A3, 0x4D65A2, //
    0x4963A1, 0x4660A0, 0x435E9F,
  ], // 5–10
  <int>[
    0x4666A4, 0x486EA9, 0x4B76AD, 0x4E7EB2, 0x5186B7, 0x538DBC, 0x5695C1, //
    0x599DC5, 0x5BA5CA, 0x5EADCF,
  ], // 10–15
  <int>[
    0x5DB1CB, 0x5CB5C6, 0x5AB9C1, 0x59BDBD, 0x58C2B9, 0x57C6B4, 0x56CAB0, //
    0x54CEAB, 0x53D2A7, 0x52D6A2,
  ], // 15–20
  <int>[
    0x4BD694, 0x44D686, 0x3ED677, 0x37D669, 0x30D65B, 0x29D64D, 0x22D63F, //
    0x1CD630, 0x15D622, 0x0ED614,
  ], // 20–25
  <int>[
    0x0ECE14, 0x0DC613, 0x0DBF13, 0x0DB712, 0x0DAF12, 0x0CA711, 0x0C9F11, //
    0x0C9810, 0x0B9010, 0x0B880F,
  ], // 25–30
  <int>[
    0x0B840E, 0x0B800E, 0x0A7B0D, 0x0A770D, 0x0A730C, 0x0A6F0B, 0x0A6B0B, //
    0x09660A, 0x09620A, 0x095E09,
  ], // 30–35
  <int>[
    0x226B08, 0x3A7807, 0x538606, 0x6B9305, 0x84A005, 0x9DAD04, 0xB5BA03, //
    0xCEC802, 0xE6D501, 0xFFE200,
  ], // 35–40
  <int>[
    0xFFDD00, 0xFFD800, 0xFFD300, 0xFFCE00, 0xFFCA00, 0xFFC500, 0xFFC000, //
    0xFFBB00, 0xFFB600, 0xFFB100,
  ], // 40–45
  <int>[
    0xFF9F00, 0xFF8E00, 0xFF7C00, 0xFF6A00, 0xFF5900, 0xFF4700, 0xFF3500, //
    0xFF2300, 0xFF1200, 0xFF0000,
  ], // 45–50
  <int>[
    0xF70000, 0xEF0000, 0xE80000, 0xE00000, 0xD80000, 0xD00000, 0xC10000, //
    0xB90000, 0xB10000,
  ], // 50–55
], unmatchedIsHeaviest: true);
