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
    bool unmatchedIsHeaviest = false,
  }) : colours = <int>[for (final c in classes) ...c],
       unmatchedClass = unmatchedIsHeaviest ? classes.length : null,
       classOf = <int>[
         for (var i = 0; i < classes.length; i++)
           for (final _ in classes[i]) i,
       ],
       classCount = classes.length + (unmatchedIsHeaviest ? 1 : 0);

  /// A legend whose colours each stand for the class of [drawnIn] at the
  /// same index of [classOf] ([rainNone] for no rain), and are drawn in its
  /// colours; an opaque colour it does not hold is [unmatchedClass] where
  /// that is given (see [unmatchedClass]).
  RainLegend.recoloured(
    this.colours,
    this.classOf, {
    required RainLegend this.drawnIn,
    this.noData,
    this.unmatchedClass,
  }) : classCount = drawnIn.classCount;

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

  /// The class an opaque pixel the legend does not hold is read as, `null`
  /// for none: for a service that draws nothing but its data and whose
  /// colours for the heaviest rain are not known, the heaviest. One near a
  /// colour of the legend ([rainLegendLooseTolerance]) is read as that
  /// colour's class instead.
  final int? unmatchedClass;

  /// The class of the pixel (r, g, b, a), 0 the lightest; [rainNoData] in
  /// the [noData] colour, [rainNone] for anything else.
  int classify(int r, int g, int b, int a) {
    if (a == 0) return rainNone;
    if (isNoData(r, g, b, a)) return rainNoData;
    if (a < rainLegendMinAlpha) return rainNone;
    final best = _nearest(r, g, b, rainLegendTolerance);
    if (best >= 0) return classOf[best];
    final unmatched = unmatchedClass;
    if (unmatched == null) return rainNone;
    final loose = _nearest(r, g, b, rainLegendLooseTolerance);
    return loose >= 0 ? classOf[loose] : unmatched;
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
  RainPalette.dwdModel1h => dwdModel1hLegend,
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

/// ICON-EU's hourly rain (`dwd:Icon-eu_reg00625_fd_sl_TOTPREC01H`) as the
/// service draws it in the radar's style `niederschlagsradar`: the radar's
/// colours, but at thresholds in mm in ten minutes (0.017 for "0.1 mm/h",
/// 2.5 for "15", 25 for "150"), read 2026-10-11 from
/// `…&request=GetLegendGraphic&layer=dwd:Icon-eu_reg00625_fd_sl_TOTPREC01H&style=niederschlagsradar&format=application/json`,
/// while the model's values are mm in an hour. Each colour is drawn as the
/// radar's class for the middle of the hourly rate it stands for; the two
/// lightest, under 0.08 mm an hour, as no rain.
final RainLegend dwdModel1hLegend = RainLegend.recoloured(
  const <int>[
    0x33FFFF, // 0.017–0.033 mm/h
    0x1ACC9A, // 0.033–0.083
    0x019934, // 0.083–0.167
    0x4DB31B, // 0.167–0.25
    0x99CC01, // 0.25–0.417
    0xCCE601, // 0.417–0.625
    0xFFFF01, // 0.625–0.833
    0xFFC401, // 0.833–1.25
    0xFF8901, // 1.25–2.5
    0xFF4501, // 2.5–3.75
    0xFE0000, // 3.75–6.25
    0xE5004C, // 6.25–8.33
    0xCC0098, // 8.33–12.5
    0x6600CB, // 12.5–25
    0x0000FE, // 25 and more
  ],
  const <int>[
    rainNone, rainNone, 0, 1, 1, 2, 2, 3, 3, 4, 5, 6, 8, 9, 10, //
  ],
  drawnIn: dwdRadarLegend,
  noData: 0x7D7D7D,
);

/// The H SAF rain's legend (`mtg_fd:h40b`):
/// `https://view.eumetsat.int/geoserver/ows?service=WMS&version=1.3.0&request=GetLegendGraphic&layer=mtg_fd:h40b&format=application/json`,
/// read 2026-10-11. Classes in mm an hour, up to the upper bound named;
/// under 0.001 transparent. Each class is drawn as the DWD radar's class
/// for its rate, so "now" outside the radars reads like the forecast that
/// follows it: under 2 mm as the radar's 0.4–1 mm, where most of the
/// satellite's light rain lies, the rest by the middle of its range.
final RainLegend hsafLegend = RainLegend.recoloured(
  const <int>[
    0xCCFFCC, // < 2
    0x99E699, // < 4
    0x66CC66, // < 7
    0x33B333, // < 10
    0x3399CC, // < 15
    0x3366FF, // < 20
    0x0000FF, // < 25
    0x6600CC, // < 30
    0x9933CC, // < 40
    0xCC0099, // < 50
    0x800080, // 50 and more
  ],
  const <int>[2, 4, 6, 7, 8, 9, 9, 9, 10, 11, 11],
  drawnIn: dwdRadarLegend,
);

/// The global ICON's six-hour legend (`dwd:Icon_reg025_fd_sl_TOTPREC06H`):
/// `https://maps.dwd.de/geoserver/dwd/wms?service=WMS&version=1.3.0&request=GetLegendGraphic&layer=dwd:Icon_reg025_fd_sl_TOTPREC06H&format=application/json`,
/// read 2026-10-11; "under 0.1 mm" is a black veil at alpha 20, no class.
/// Each class is drawn as the DWD radar's class for its mean rate an hour
/// (the class's middle over six hours), so the forecast reads like the
/// radar: 0.5–1 mm in six hours is the radar's lightest, 200–300 mm its
/// 30–45 mm an hour; 0.1–0.5 mm, under 0.1 mm an hour, is no rain.
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
  const <int>[
    // 0.1–0.5 mm in six hours is under 0.1 an hour: no rain, as on the radar.
    rainNone, 0, 1, 2, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 8, 9, 9, 9, 10, 11, //
  ],
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
const List<List<int>> _noaaClasses = <List<int>>[
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
];

/// The DWD radar class each of NOAA's 5 dBZ classes is drawn as: its rain
/// rate by the Marshall–Palmer relation (Z = 200 R^1.6) at the middle of
/// the class, so NOAA's green (25–30 dBZ, 1.3–2.7 mm an hour) is the
/// radar's 1–2 mm green, not a light rain's. Under 5 dBZ, under 0.08 mm an
/// hour, is no rain; the heaviest, unseen colours (55 dBZ and more, over
/// 100 mm an hour) the radar's 100–150 mm.
const List<int> _noaaDrawnAs = <int>[rainNone, 0, 1, 2, 2, 3, 5, 7, 9, 10, 11];

/// NOAA's legend as the soft rain reads it: see [_noaaClasses] and
/// [_noaaDrawnAs].
final RainLegend noaaRadarLegend = RainLegend.recoloured(
  <int>[for (final c in _noaaClasses) ...c],
  <int>[
    for (var i = 0; i < _noaaClasses.length; i++)
      for (final _ in _noaaClasses[i]) _noaaDrawnAs[i],
  ],
  drawnIn: dwdRadarLegend,
  unmatchedClass: 13,
);
