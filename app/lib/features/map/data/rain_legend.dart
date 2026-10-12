import 'dart:math' as math;

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
  RainPalette.n0q => n0qLegend,
  RainPalette.knmi => knmiRadarLegend,
  RainPalette.fmi => fmiRadarLegend,
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
/// radar's class for the middle of the hourly rate it stands for; the three
/// lightest, under 0.17 mm an hour, as no rain.
///
/// That drizzle falls in the radar's lightest class, 0.1–0.2 mm an hour,
/// and the models spread it wide where neither the satellite at "Now" nor
/// most radars show anything: drawn, the forecast at +15 minutes looked far
/// wetter than "Now" beside it. So the models' rain under 0.2 mm an hour is
/// no rain (here and in [dwdModel6hLegend]); the radars, the satellite and
/// the HRRR keep their lightest class.
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
    // Under 0.17 mm an hour: drizzle the satellite never shows, no rain.
    rainNone, rainNone, rainNone, 1, 1, 2, 2, 3, 3, 4, 5, 6, 8, 9, 10, //
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
/// radar: 1–2 mm in six hours is the radar's 0.2–0.4 mm, 200–300 mm its
/// 30–45 mm an hour; under 1 mm, under 0.17 mm an hour, is no rain, the
/// drizzle [dwdModel1hLegend] leaves out too.
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
    // Under 1 mm in six hours, under 0.17 an hour: drizzle, no rain.
    rainNone,
    rainNone,
    1,
    2,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    7,
    7,
    8,
    8,
    8,
    9,
    9,
    9,
    10,
    11, //
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

/// The lower bounds of the DWD radar's classes ([dwdRadarLegend]), mm an
/// hour, the lightest first.
const List<double> dwdRadarClassFloors = <double>[
  0.1, 0.2, 0.4, 1, 2, 3, 5, 7.5, 10, 15, 30, 45, 75, 100, 150, //
];

/// The DWD radar's class for [rate] mm an hour; [rainNone] under its
/// lightest.
int dwdRadarClassOf(double rate) {
  var k = rainNone;
  for (var i = 0; i < dwdRadarClassFloors.length; i++) {
    if (rate >= dwdRadarClassFloors[i]) k = i;
  }
  return k;
}

/// The rain rate, mm an hour, of a reflectivity of [dbz] by the
/// Marshall–Palmer relation Z = 200 R^1.6.
double marshallPalmerRate(double dbz) =>
    math.pow(math.pow(10, dbz / 10) / 200, 1 / 1.6).toDouble();

/// The reflectivity under which the N0Q ramp ([n0qLegend]) is no rain:
/// some 0.08 mm an hour.
const double n0qMinRainDbz = 5;

/// The reflectivity [n0qColours] index [i] stands for, in dBZ.
double n0qDbzOf(int i) => -32 + 0.5 * i;

/// The Iowa Environmental Mesonet's 8-bit NEXRAD reflectivity ramp (N0Q),
/// which its HRRR forecast tiles are drawn in: the lookup table of
/// `composite_n0q` at
/// `https://mesonet.agron.iastate.edu/GIS/rasters.php?rid=2`, read
/// 2026-10-11, without index 0 ("missing", which the tiles leave
/// transparent). Colour [i] is [n0qDbzOf] `i` dBZ, from -32 to 95 in steps
/// of half a dBZ; each line's comment is its first.
const List<int> n0qColours = <int>[
  0x85718F, 0x85728F, 0x86738D, 0x87758B, 0x87768B, 0x887789, // -32
  0x897987, 0x897A87, 0x8A7B85, 0x8B7D84, 0x8B7E84, 0x8C7F82, // -29
  0x8D8180, 0x8D8280, 0x8E837E, 0x8F847C, 0x8F857C, 0x90877B, // -26
  0x918879, 0x918979, 0x928B77, 0x938D75, 0x969153, 0x989457, // -23
  0x9B975B, 0x9D9A60, 0xA09D64, 0xA3A068, 0xA5A36D, 0xA8A671, // -20
  0xAAA976, 0xADAC7A, 0xB0AF7E, 0xB2B283, 0xB7B88C, 0xBABB90, // -17
  0xBDBE94, 0xBFC199, 0xC2C49D, 0xC4C7A2, 0xC7CAA6, 0xCACDAA, // -14
  0xCCD0AF, 0xD2D4B4, 0xCFD2B4, 0xC9CCB4, 0xC6C9B4, 0xC3C7B4, // -11
  0xC0C4B4, 0xBDC1B4, 0xB9BEB4, 0xB6BBB4, 0xB3B9B4, 0xB0B6B4, // -8
  0xADB3B4, 0xAAB0B4, 0xA4ABB4, 0xA0A8B4, 0x9DA5B4, 0x9AA2B4, // -5
  0x97A0B4, 0x949DB4, 0x919AB4, 0x949BB5, 0x9098B4, 0x8C95B3, // -2
  0x8892B2, 0x808CB0, 0x7C89AF, 0x7886AE, 0x7483AC, 0x7080AB, // 1
  0x6C7DAA, 0x6779A9, 0x6376A8, 0x5F73A7, 0x5B70A6, 0x576DA4, // 4
  0x4F67A2, 0x4B64A1, 0x4761A0, 0x435E9F, 0x415B9E, 0x4361A2, // 7
  0x4568A6, 0x486FAA, 0x4A76AE, 0x4D7DB2, 0x4F84B6, 0x518BBB, // 10
  0x5699C3, 0x599FC7, 0x5BA6CB, 0x5EADCF, 0x60B4D4, 0x62BBD8, // 13
  0x65C2DC, 0x67C9E0, 0x6AD0E4, 0x6FD6E8, 0x68D6D7, 0x59D6B3, // 16
  0x52D6A2, 0x4BD690, 0x43D67E, 0x3CD66D, 0x35D65B, 0x11D518, // 19
  0x11D117, 0x10CD17, 0x10C816, 0x10C416, 0x0FBC15, 0x0FB714, // 22
  0x0EB314, 0x0EAF13, 0x0EAB13, 0x0DA612, 0x0DA212, 0x0D9E11, // 25
  0x0C9911, 0x0C9510, 0x0C9110, 0x0B880F, 0x0B840E, 0x0A800E, // 28
  0x0A7C0D, 0x0A770D, 0x09730C, 0x096F0C, 0x096B0B, 0x08660B, // 31
  0x08620A, 0x095E09, 0x327308, 0x467D08, 0x5B8807, 0x6F9207, // 34
  0x849D06, 0x98A806, 0xADB205, 0xC1BD05, 0xD6C704, 0xEAD204, // 37
  0xFFE200, 0xFFD800, 0xFFD300, 0xFFCE00, 0xFFC900, 0xFFC400, // 40
  0xFFC000, 0xFFBB00, 0xFFB600, 0xFFB100, 0xFFAC00, 0xFFA700, // 43
  0xFFA200, 0xFF9900, 0xFF9400, 0xFF8F00, 0xFF8A00, 0xFF8500, // 46
  0xFF8000, 0xFF0000, 0xF80000, 0xF10000, 0xEA0000, 0xE30000, // 49
  0xD50000, 0xCD0000, 0xC60000, 0xBF0000, 0xB80000, 0xB10000, // 52
  0xAA0000, 0xA30000, 0x9B0000, 0x940000, 0x8D0000, 0x7F0000, // 55
  0x780000, 0x710000, 0xFFFFFF, 0xFFF5FF, 0xFFEAFF, 0xFFDFFF, // 58
  0xFFD4FF, 0xFFC9FF, 0xFFBEFF, 0xFFB3FF, 0xFF9DFF, 0xFF92FF, // 61
  0xFF75FF, 0xFC6BFD, 0xF960FA, 0xF656F7, 0xF34BF4, 0xF040F1, // 64
  0xED36EF, 0xEA2BEC, 0xE720E9, 0xE10BE3, 0xB200FF, 0xAC00FC, // 67
  0xA400F7, 0x9B00F4, 0x9300EF, 0x8800EA, 0x8300E8, 0x7900E2, // 70
  0x7200DD, 0x6900DB, 0x05ECF0, 0x05EBF0, 0x05EAF0, 0x05DDE0, // 73
  0x05DCE0, 0x05DBE0, 0x05CDD0, 0x05CCD0, 0x04BDC0, 0x04BCC0, // 76
  0x04BBC0, 0x04AEB0, 0x04ADB0, 0x049EA0, 0x049DA0, 0x049CA0, // 79
  0x038E90, 0x038D90, 0x038C90, 0x037E80, 0x037D80, 0x036F70, // 82
  0x036E70, 0x036D70, 0x025F60, 0x025E60, 0x024F50, 0x024E50, // 85
  0x024D50, 0x023F40, 0x023E40, 0x023D40, 0x013030, 0x012F30, // 88
  0x012020, 0x011F20, 0x011E20, 0x3A67B5, 0x3A66B5, 0x3A65B5, // 91
  0x3A64B5, 0x3A63B5, 0x3A62B5, // 94
];

/// The N0Q ramp as the soft rain reads it: each colour drawn as the DWD
/// radar's class for its rate by the Marshall–Palmer relation
/// ([marshallPalmerRate]), as NOAA's ramp is ([noaaRadarLegend]); under
/// [n0qMinRainDbz] no rain, from it to the radar's lightest class at least.
final RainLegend n0qLegend = RainLegend.recoloured(n0qColours, <int>[
  for (var i = 0; i < n0qColours.length; i++)
    if (n0qDbzOf(i) < n0qMinRainDbz)
      rainNone
    else
      math.max(0, dwdRadarClassOf(marshallPalmerRate(n0qDbzOf(i)))),
], drawnIn: dwdRadarLegend);

/// The lowest value of the KNMI radar's composite [knmiColours] draws:
/// a reflectivity byte of 78, some 0.1 mm an hour.
const int knmiLowestValue = 78;

/// The rain rate, mm an hour, of the KNMI composite's byte [value]: its
/// reflectivity in half dBZ, turned into rain as KNMI's server does,
/// R = 10^((value − 109) / 32), Marshall–Palmer on the composite's scale.
double knmiRateOf(int value) => math.pow(10, (value - 109) / 32).toDouble();

/// The colours the KNMI's radar service (`RAD_NL25_PCP_CM`, style
/// `precip-blue-transparent/nearest`) draws for the composite's bytes from
/// [knmiLowestValue] up, one each: a continuous ramp over 0.1 to 100 mm an
/// hour on a log scale, white-blue through blue to violet. Its legend
/// graphic labels the ramp only roughly and the style is not published, so
/// the ramp was read 2026-10-11 off the service itself: for cells of one
/// colour in images over the Netherlands, its `GetFeatureInfo` gave the
/// rate, every byte from 78 (0.11 mm an hour) to 168 (70 mm an hour) its
/// own colour. Bytes 163 and 167 did not fall and are their neighbours'
/// mean; each line's comment is its first rate. Under byte 78 the service
/// draws nothing, as it does for dry and for beyond the radars' reach.
const List<int> knmiColours = <int>[
  0xCDF3FF, 0xCBF1FF, 0xC7EFFF, 0xC4EDFF, 0xC1EBFF, 0xBEE9FF, // 0.11
  0xBAE7FF, 0xB8E6FF, 0xB4E3FF, 0xB1E2FF, 0xADDFFF, 0xABDEFF, // 0.17
  0xA7DCFF, 0xA5DAFF, 0xA1D8FF, 0x9ED6FF, 0x9AD4FF, 0x98D2FF, // 0.25
  0x94D0FF, 0x92CFFF, 0x8ECCFF, 0x8BCAFF, 0x86C7FF, 0x83C4FF, // 0.39
  0x7FC0FF, 0x7CBEFF, 0x77BAFF, 0x74B8FF, 0x70B4FF, 0x6DB2FF, // 0.60
  0x68AEFF, 0x65ACFF, 0x5CA9FF, 0x55A7FF, 0x4AA4FF, 0x42A2FF, // 0.93
  0x37A0FF, 0x309EFF, 0x259BFF, 0x1E9AFF, 0x1397FF, 0x0B95FF, // 1.43
  0x0192FF, 0x0190FF, 0x018CFF, 0x018AFF, 0x0186FF, 0x0183FF, // 2.21
  0x017FFF, 0x017DFF, 0x0179FF, 0x0177FF, 0x0173FF, 0x0170FF, // 3.40
  0x016DFF, 0x016BFF, 0x0168FF, 0x0166FF, 0x0163FF, 0x0161FF, // 5.23
  0x015EFF, 0x015CFF, 0x0159FF, 0x0157FF, 0x0153FF, 0x0151FF, // 8.06
  0x014DFF, 0x014AFF, 0x0147FF, 0x0144FF, 0x0141FF, 0x013EFF, // 12.4
  0x013BFF, 0x0138FF, 0x0134FF, 0x0334FD, 0x0734F9, 0x0B34F7, // 19.1
  0x0F34F3, 0x1234F0, 0x1734EC, 0x1A34EA, 0x1F34E6, 0x2234E4, // 29.4
  0x2734E0, 0x2934DC, 0x2B34D9, 0x2C34D7, 0x2E34D1, 0x2F34CF, // 45.3
  0x3134CD, // 69.8
];

/// The KNMI ramp past the bytes seen ([knmiColours]): its colours at about
/// 85 and 100 mm an hour as the legend graphic draws them, the radar's
/// 75–100 and 100–150 mm classes.
const List<int> _knmiHeaviest = <int>[0x3534C3, 0x3834BD];

/// The KNMI radar's legend as the soft rain reads it: each colour drawn as
/// the DWD radar's class for its rate ([knmiRateOf]), so the Dutch radar
/// reads like the German one beside it.
final RainLegend knmiRadarLegend = RainLegend.recoloured(
  <int>[...knmiColours, ..._knmiHeaviest],
  <int>[
    for (var i = 0; i < knmiColours.length; i++)
      math.max(0, dwdRadarClassOf(knmiRateOf(knmiLowestValue + i))),
    12,
    13,
  ],
  drawnIn: dwdRadarLegend,
);

/// The FMI's rain rate composite (`Radar:suomi_rr_eureffin`): its colour
/// map, `…/geoserver/Radar/ows?service=WMS&version=1.3.0&request=GetLegendGraphic&layer=suomi_rr_eureffin&format=application/json`,
/// read 2026-10-11, a ramp between these colours at these values in
/// hundredths of a mm an hour. Under 0.07 mm an hour it is transparent, as
/// dry is; past 63 mm it runs on towards the "no data" grey, fading.
const List<(int, int)> fmiRampStops = <(int, int)>[
  (7, 0x6CEBF3),
  (14, 0x58C797),
  (34, 0x409857),
  (86, 0xF1F35A),
  (216, 0xDFC40A),
  (398, 0xEB951A),
  (1000, 0xE85616),
  (2513, 0xCE0202),
  (6313, 0x830A46),
  // "No data", which the ramp fades into; under the alpha that counts as
  // rain from about 210 mm an hour.
  (65530, 0xCCCCCC),
];

/// The highest value of the FMI's ramp still drawn opaque enough to count
/// as rain ([rainLegendMinAlpha]), hundredths of a mm an hour: past it the
/// ramp fades towards "no data" at 15 %.
const int _fmiHighestValue = 21000;

/// The FMI ramp's colour at [value], hundredths of a mm an hour: each
/// channel interpolated between the stops around it, as GeoServer draws a
/// ramp.
int fmiColourAt(int value) {
  for (var i = 1; i < fmiRampStops.length; i++) {
    final (to, c1) = fmiRampStops[i];
    if (value > to) continue;
    final (from, c0) = fmiRampStops[i - 1];
    final t = (value - from) / (to - from);
    int channel(int shift) {
      final a = c0 >> shift & 0xFF;
      final b = c1 >> shift & 0xFF;
      return (a + (b - a) * t).round();
    }

    return channel(16) << 16 | channel(8) << 8 | channel(0);
  }
  return fmiRampStops.last.$2;
}

/// Every colour of the FMI's ramp from its lowest value to
/// [_fmiHighestValue], each once, with the value (hundredths of a mm an
/// hour) in the middle of the run it is drawn for.
final List<(int, double)> _fmiRamp = () {
  final out = <(int, double)>[];
  final seen = <int>{};
  var start = fmiRampStops.first.$1;
  var colour = fmiColourAt(start);
  for (var v = start + 1; v <= _fmiHighestValue + 1; v++) {
    final next = v > _fmiHighestValue ? -1 : fmiColourAt(v);
    if (next == colour) continue;
    if (seen.add(colour)) out.add((colour, (start + v - 1) / 2));
    start = v;
    colour = next;
  }
  return out;
}();

/// The FMI radar's legend as the soft rain reads it: each colour of its
/// ramp drawn as the DWD radar's class for its rate (under 0.1 mm an hour
/// no rain, as on the DWD's radar); "no data" the grey `#CCCCCC` the
/// service draws at 15 % beyond its radars' reach.
final RainLegend fmiRadarLegend = RainLegend.recoloured(
  <int>[for (final (colour, _) in _fmiRamp) colour],
  <int>[for (final (_, value) in _fmiRamp) dwdRadarClassOf(value / 100)],
  drawnIn: dwdRadarLegend,
  noData: 0xCCCCCC,
);
