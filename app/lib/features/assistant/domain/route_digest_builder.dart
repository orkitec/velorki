import 'dart:math' as math;

import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Building the route digest the `describe` step is given: what a route runs
/// over, where it climbs, which settlements it passes through and where a
/// rider could stop. Pure: the caller fetches the router's messages and the
/// gazetteer rows, this only measures them against the line.

/// The settlement kinds a route can pass through, and how far from the line
/// a settlement's centre may be for the route to count as passing it.
const Map<String, double> digestTownReachM = <String, double>{
  'city': 2000,
  'town': 1000,
  'village': 500,
};

/// The gazetteer POI kinds offered as places to stop, most useful first.
const List<String> digestPlaceKinds = <String>[
  'drinking_water',
  'cafe',
  'bakery',
  'toilets',
  'bicycle_shop',
  'bicycle_repair_station',
  'viewpoint',
  'water',
  'beach',
  'station',
];

/// How far off the line a place to stop may be, in metres.
const double digestPlaceReachM = 300;

/// The most stretches, climbs, towns and places a digest carries; the relay
/// accepts no more.
const int digestMaxStretches = 60;

/// See [digestMaxStretches].
const int digestMaxClimbs = 20;

/// See [digestMaxStretches].
const int digestMaxTowns = 30;

/// See [digestMaxStretches].
const int digestMaxPlaces = 40;

/// The shortest stretch kept on its own, in metres; shorter ones join a
/// neighbour.
const double digestMinStretchM = 300;

/// A climb counts from this much gain…
const double digestClimbMinGainM = 40;

/// …at this average gradient, in percent.
const double digestClimbMinGrade = 3;

/// A row of the gazetteer near the route: a settlement or a POI.
class DigestCandidate {
  /// Creates a candidate.
  const DigestCandidate({
    required this.name,
    required this.kind,
    required this.position,
  });

  /// Its name, empty for an unnamed POI.
  final String name;

  /// The gazetteer kind: `city`, `village`, `cafe`, `drinking_water`, …
  final String kind;

  /// Where it is.
  final LatLng position;
}

/// Builds the digest of the route along [geometry].
///
/// [messages] are the router's messages along the same line (see
/// `TrackSurfaceService.matchWays`); without them the digest has no
/// stretches. The gradients come from the elevations in [geometry], or from
/// the messages' when the geometry has none. [candidates] are gazetteer rows
/// around the line; only the settlements of [digestTownReachM] and the POIs
/// of [digestPlaceKinds] close enough to it are kept.
RouteDigest buildRouteDigest({
  required List<TrackPoint> geometry,
  List<SegmentMessage> messages = const <SegmentMessage>[],
  List<DigestCandidate> candidates = const <DigestCandidate>[],
  String? profile,
}) {
  if (geometry.length < 2) return RouteDigest(loop: false, profile: profile);
  final line = _Line(geometry);
  if (line.length < 1) return RouteDigest(loop: false, profile: profile);

  final loop =
      haversineMeters(geometry.first.pos, geometry.last.pos) <= 300 &&
      line.length > 1000;
  final profileOfHeights = _Heights.of(line, geometry, messages);

  return RouteDigest(
    profile: profile,
    loop: loop,
    stretches: messages.isEmpty
        ? const <DigestStretch>[]
        : _stretches(line, profileOfHeights, messages),
    climbs: profileOfHeights == null
        ? const <DigestClimb>[]
        : _climbs(profileOfHeights),
    towns: _towns(line, candidates),
    places: _places(line, candidates),
  );
}

/* ---------------------------------------------------------------- the line */

/// The route as a polyline measured along its length, with a grid of its
/// segments for "how far is this point from the line".
class _Line {
  _Line(List<TrackPoint> geometry)
    : positions = [for (final p in geometry) p.pos],
      along = cumulativeDistancesMeters([for (final p in geometry) p.pos]) {
    final first = positions.first;
    _lat0 = first.lat;
    _lon0 = first.lon;
    _cos = math.cos(_lat0 * math.pi / 180).abs().clamp(0.01, 1).toDouble();
    _xy = [for (final p in positions) _project(p)];
    for (var i = 0; i + 1 < _xy.length; i++) {
      final a = _xy[i];
      final b = _xy[i + 1];
      final x0 = (math.min(a.x, b.x) / _cell).floor();
      final x1 = (math.max(a.x, b.x) / _cell).floor();
      final y0 = (math.min(a.y, b.y) / _cell).floor();
      final y1 = (math.max(a.y, b.y) / _cell).floor();
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          (_grid[_key(x, y)] ??= <int>[]).add(i);
        }
      }
    }
  }

  static const double _cell = 500;
  static const double _mPerDeg = 111320;

  final List<LatLng> positions;
  final List<double> along;
  late final double _lat0;
  late final double _lon0;
  late final double _cos;
  late final List<math.Point<double>> _xy;
  final Map<int, List<int>> _grid = <int, List<int>>{};

  double get length => along.last;

  math.Point<double> _project(LatLng p) => math.Point<double>(
    (p.lon - _lon0) * _cos * _mPerDeg,
    (p.lat - _lat0) * _mPerDeg,
  );

  static int _key(int x, int y) => x * 1000003 + y;

  /// The point of the line [d] metres from its start.
  LatLng at(double d) {
    if (d <= 0) return positions.first;
    if (d >= length) return positions.last;
    var lo = 0;
    var hi = along.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (along[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = along[hi] - along[lo];
    final t = span <= 0 ? 0.0 : (d - along[lo]) / span;
    final a = positions[lo];
    final b = positions[hi];
    return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  }

  /// Where [p] comes closest to the line, when that is within [reach]
  /// metres: how far along and how far off. The first such point wins a tie,
  /// so a loop's start is km 0, not its last metre.
  ({double along, double off})? nearest(LatLng p, double reach) {
    final q = _project(p);
    final x0 = ((q.x - reach) / _cell).floor();
    final x1 = ((q.x + reach) / _cell).floor();
    final y0 = ((q.y - reach) / _cell).floor();
    final y1 = ((q.y + reach) / _cell).floor();
    final seen = <int>{};
    var best = double.infinity;
    var bestAlong = 0.0;
    var bestIndex = -1;
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        final cell = _grid[_key(x, y)];
        if (cell == null) continue;
        for (final i in cell) {
          if (!seen.add(i)) continue;
          final a = _xy[i];
          final b = _xy[i + 1];
          final dx = b.x - a.x;
          final dy = b.y - a.y;
          final len2 = dx * dx + dy * dy;
          var t = len2 <= 0
              ? 0.0
              : ((q.x - a.x) * dx + (q.y - a.y) * dy) / len2;
          t = t.clamp(0.0, 1.0);
          final px = a.x + dx * t - q.x;
          final py = a.y + dy * t - q.y;
          final d = math.sqrt(px * px + py * py);
          if (d < best - 1e-6 || (d < best + 1e-6 && i < bestIndex)) {
            best = d;
            bestIndex = i;
            bestAlong = along[i] + (along[i + 1] - along[i]) * t;
          }
        }
      }
    }
    if (bestIndex < 0 || best > reach) return null;
    return (along: bestAlong, off: best);
  }
}

/* ------------------------------------------------------------- the heights */

/// The route's elevation, resampled every [step] metres and smoothed, with
/// the gradient over about 100 m at every sample.
class _Heights {
  _Heights(this.step, this.distances, this.elevations, this.grades);

  final double step;

  /// Distance of every sample from the start.
  final List<double> distances;

  /// Smoothed elevation at every sample.
  final List<double> elevations;

  /// Gradient in percent from every sample to the next, over about 100 m.
  final List<double> grades;

  /// The heights along [line], or `null` when neither the geometry nor the
  /// messages carry any.
  static _Heights? of(
    _Line line,
    List<TrackPoint> geometry,
    List<SegmentMessage> messages,
  ) {
    var known = <({double d, double e})>[
      for (var i = 0; i < geometry.length; i++)
        if (geometry[i].ele case final double e) (d: line.along[i], e: e),
    ];
    if (known.length < 2 && messages.isNotEmpty) {
      final total = messages.fold<double>(0, (s, m) => s + m.distanceM);
      final scale = total > 0 ? line.length / total : 1.0;
      var d = 0.0;
      known = <({double d, double e})>[];
      for (final m in messages) {
        d += m.distanceM * scale;
        known.add((d: d, e: m.elevationM));
      }
    }
    if (known.length < 2) return null;

    final length = line.length;
    final step = math.max(25.0, length / 8000);
    final n = math.max(1, (length / step).ceil());
    final distances = <double>[
      for (var k = 0; k <= n; k++) math.min(k * step, length),
    ];

    // Linear interpolation over the known heights.
    final raw = List<double>.filled(distances.length, 0);
    var j = 0;
    for (var k = 0; k < distances.length; k++) {
      final d = distances[k];
      while (j + 1 < known.length && known[j + 1].d < d) {
        j++;
      }
      if (d <= known.first.d) {
        raw[k] = known.first.e;
      } else if (j + 1 >= known.length) {
        raw[k] = known.last.e;
      } else {
        final a = known[j];
        final b = known[j + 1];
        final span = b.d - a.d;
        raw[k] = span <= 0 ? b.e : a.e + (b.e - a.e) * (d - a.d) / span;
      }
    }

    // A moving average over ±50 m irons out the steps of the elevation model.
    final w = math.max(1, (50 / step).round());
    final smooth = List<double>.filled(raw.length, 0);
    var sum = 0.0;
    var lo = 0;
    var hi = -1;
    for (var k = 0; k < raw.length; k++) {
      final from = math.max(0, k - w);
      final to = math.min(raw.length - 1, k + w);
      while (hi < to) {
        sum += raw[++hi];
      }
      while (lo < from) {
        sum -= raw[lo++];
      }
      smooth[k] = sum / (hi - lo + 1);
    }

    final grades = List<double>.filled(math.max(0, raw.length - 1), 0);
    for (var k = 0; k < grades.length; k++) {
      final a = math.max(0, k - w + 1);
      final b = math.min(raw.length - 1, k + w);
      final run = distances[b] - distances[a];
      grades[k] = run <= 0 ? 0 : (smooth[b] - smooth[a]) / run * 100;
    }
    return _Heights(step, distances, smooth, grades);
  }

  /// The smoothed elevation [d] metres from the start.
  double at(double d) {
    if (d <= 0) return elevations.first;
    final k = (d / step).floor();
    if (k >= distances.length - 1) return elevations.last;
    final span = distances[k + 1] - distances[k];
    final t = span <= 0 ? 0.0 : (d - distances[k]) / span;
    return elevations[k] + (elevations[k + 1] - elevations[k]) * t;
  }

  /// The steepest gradient between [from] and [to], signed.
  double steepest(double from, double to, {bool upOnly = false}) {
    if (grades.isEmpty) return 0;
    final a = (from / step).floor().clamp(0, grades.length - 1);
    final b = ((to / step).ceil() - 1).clamp(a, grades.length - 1);
    var best = 0.0;
    for (var k = a; k <= b; k++) {
      final g = grades[k];
      if (upOnly ? g > best : g.abs() > best.abs()) best = g;
    }
    return best;
  }
}

/* --------------------------------------------------------------- stretches */

/// The road class of a way: its `highway` without `_link`, `ferry`, or
/// `unknown`.
String _road(Map<String, String> tags) {
  final highway = tags['highway'];
  if (highway == null || highway.isEmpty) {
    return tags['route'] == 'ferry' ? 'ferry' : 'unknown';
  }
  return _tagValue(
    highway.endsWith('_link')
        ? highway.substring(0, highway.length - 5)
        : highway,
  );
}

/// The relay takes a tag value only as OSM writes them, short and lower
/// case; anything a mapper made up instead reads as `unknown` rather than
/// failing the whole request.
final RegExp _tagValuePattern = RegExp(r'^[a-z0-9_:;.-]{1,32}$');

String _tagValue(String? value) =>
    value != null && _tagValuePattern.hasMatch(value) ? value : 'unknown';

const Set<String> _gravelSurfaces = <String>{
  'gravel',
  'fine_gravel',
  'compacted',
  'pebblestone',
};

/// The coarse surface class a stretch is split on: one asphalt and one
/// concrete way are the same stretch, gravel and dirt are not.
String _surfaceClass(String surface, String road) {
  if (SurfaceStats.pavedSurfaces.contains(surface)) return 'paved';
  if (_gravelSurfaces.contains(surface)) return 'gravel';
  if (SurfaceStats.unpavedSurfaces.contains(surface)) return 'unpaved';
  if (SurfaceStats.unpavedByDefaultHighways.contains(road)) return 'unpaved';
  return 'unknown';
}

/// The slope class a stretch is split on.
int _gradeClass(double grade) {
  if (grade <= -6) return -2;
  if (grade <= -2.5) return -1;
  if (grade < 2.5) return 0;
  if (grade < 6) return 1;
  return 2;
}

/// One run of the route while the stretches are being merged.
class _Piece {
  _Piece(this.from, this.to);

  double from;
  double to;
  final Map<String, double> roads = <String, double>{};
  final Map<String, double> surfaces = <String, double>{};
  final Map<String, double> surfaceClasses = <String, double>{};
  final Map<int, double> gradeClasses = <int, double>{};

  double get length => to - from;

  String get road => _dominant(roads);
  String get surfaceClass => _dominant(surfaceClasses);
  int get gradeClass => _dominant(gradeClasses);

  void add(
    String road,
    String surface,
    String surfaceClass,
    int grade,
    double d,
  ) {
    roads[road] = (roads[road] ?? 0) + d;
    surfaces[surface] = (surfaces[surface] ?? 0) + d;
    surfaceClasses[surfaceClass] = (surfaceClasses[surfaceClass] ?? 0) + d;
    gradeClasses[grade] = (gradeClasses[grade] ?? 0) + d;
  }

  void absorb(_Piece other) {
    from = math.min(from, other.from);
    to = math.max(to, other.to);
    void sum<K>(Map<K, double> into, Map<K, double> from) {
      for (final e in from.entries) {
        into[e.key] = (into[e.key] ?? 0) + e.value;
      }
    }

    sum(roads, other.roads);
    sum(surfaces, other.surfaces);
    sum(surfaceClasses, other.surfaceClasses);
    sum(gradeClasses, other.gradeClasses);
  }

  bool sameAs(_Piece other) =>
      road == other.road &&
      surfaceClass == other.surfaceClass &&
      gradeClass == other.gradeClass;

  int likeness(_Piece other) =>
      (road == other.road ? 2 : 0) +
      (surfaceClass == other.surfaceClass ? 1 : 0) +
      (gradeClass == other.gradeClass ? 1 : 0);

  static K _dominant<K>(Map<K, double> lengths) {
    late K best;
    var bestLength = -1.0;
    for (final e in lengths.entries) {
      if (e.value > bestLength) {
        best = e.key;
        bestLength = e.value;
      }
    }
    return best;
  }
}

List<DigestStretch> _stretches(
  _Line line,
  _Heights? heights,
  List<SegmentMessage> messages,
) {
  final length = line.length;
  // The router measured its own length, which differs from the line's by a
  // few per cent; its messages are stretched onto the line.
  final total = messages.fold<double>(0, (s, m) => s + m.distanceM);
  if (total <= 0) return const <DigestStretch>[];
  final scale = length / total;
  final ends = <double>[];
  var d = 0.0;
  for (final m in messages) {
    d += m.distanceM * scale;
    ends.add(d);
  }

  final step = heights?.step ?? math.max(25.0, length / 8000);
  final pieces = <_Piece>[];
  var j = 0;
  for (var from = 0.0; from < length; from += step) {
    final to = math.min(from + step, length);
    final mid = (from + to) / 2;
    while (j < ends.length - 1 && ends[j] < mid) {
      j++;
    }
    final tags = messages[j].wayTags;
    final road = _road(tags);
    final surface = _tagValue(tags['surface']);
    final surfaceClass = _surfaceClass(surface, road);
    final grade = heights == null
        ? 0
        : _gradeClass(
            heights.grades.isEmpty
                ? 0
                : heights.grades[(from / heights.step).floor().clamp(
                    0,
                    heights.grades.length - 1,
                  )],
          );
    final piece = _Piece(from, to)
      ..add(road, surface, surfaceClass, grade, to - from);
    if (pieces.isNotEmpty && pieces.last.sameAs(piece)) {
      pieces.last.absorb(piece);
    } else {
      pieces.add(piece);
    }
  }

  var threshold = math.max(
    digestMinStretchM,
    length / (digestMaxStretches * 2),
  );
  _merge(pieces, threshold);
  while (pieces.length > digestMaxStretches) {
    threshold *= 1.4;
    _merge(pieces, threshold);
  }

  return [
    for (final p in pieces)
      DigestStretch(
        fromKm: _round(p.from / 1000, 2),
        toKm: _round(p.to / 1000, 2),
        road: p.road,
        surface: _Piece._dominant(p.surfaces),
        avgGrade: heights == null
            ? 0
            : _grade((heights.at(p.to) - heights.at(p.from)) / p.length * 100),
        maxGrade: heights == null ? 0 : _grade(heights.steepest(p.from, p.to)),
        start: _point(line.at(p.from)),
        end: _point(line.at(p.to)),
      ),
  ];
}

/// Joins every piece shorter than [threshold] to its likelier neighbour,
/// shortest first, and neighbours that end up alike to each other.
void _merge(List<_Piece> pieces, double threshold) {
  while (pieces.length > 1) {
    var shortest = -1;
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i].length >= threshold) continue;
      if (shortest < 0 || pieces[i].length < pieces[shortest].length) {
        shortest = i;
      }
    }
    if (shortest < 0) break;
    final piece = pieces[shortest];
    final left = shortest > 0 ? pieces[shortest - 1] : null;
    final right = shortest + 1 < pieces.length ? pieces[shortest + 1] : null;
    final _Piece into;
    if (left == null) {
      into = right!;
    } else if (right == null) {
      into = left;
    } else {
      final l = piece.likeness(left);
      final r = piece.likeness(right);
      into = l != r
          ? (l > r ? left : right)
          // The shorter one on a tie, so a run of short pieces pairs up
          // rather than rolling into one ever longer stretch.
          : (left.length <= right.length ? left : right);
    }
    into.absorb(piece);
    pieces.removeAt(shortest);
    // The neighbour may now look like the piece on its other side.
    final at = pieces.indexOf(into);
    if (at > 0 && pieces[at - 1].sameAs(into)) {
      pieces[at - 1].absorb(into);
      pieces.removeAt(at);
    } else if (at + 1 < pieces.length && pieces[at + 1].sameAs(into)) {
      into.absorb(pieces[at + 1]);
      pieces.removeAt(at + 1);
    }
  }
}

/* ------------------------------------------------------------------ climbs */

List<DigestClimb> _climbs(_Heights heights) {
  final e = heights.elevations;
  final s = heights.distances;
  final found = <DigestClimb>[];

  void close(int start, int top) {
    // A lead-in that barely rises is not part of the climb.
    while (start < top &&
        e[start + 1] - e[start] < 0.01 * (s[start + 1] - s[start])) {
      start++;
    }
    final gain = e[top] - e[start];
    final run = s[top] - s[start];
    if (run <= 0) return;
    final grade = gain / run * 100;
    if (gain < digestClimbMinGainM || grade < digestClimbMinGrade) return;
    found.add(
      DigestClimb(
        startKm: _round(s[start] / 1000, 2),
        lengthKm: _round(run / 1000, 2),
        gainM: gain.roundToDouble(),
        avgGrade: _grade(grade),
        maxGrade: _grade(heights.steepest(s[start], s[top], upOnly: true)),
      ),
    );
  }

  var low = 0;
  var start = -1;
  var top = 0;
  for (var k = 1; k < e.length; k++) {
    if (start < 0) {
      // The last of a flat's lowest points: a climb starts where the road
      // leaves the flat, not where the flat began.
      if (e[k] <= e[low]) {
        low = k;
      } else if (e[k] - e[low] >= 10) {
        start = low;
        top = k;
      }
      continue;
    }
    if (e[k] > e[top]) {
      top = k;
      continue;
    }
    // A climb ends at its top once the road has dropped clearly below it, or
    // has stayed below it for a kilometre: a long flat is not part of it.
    final drop = e[top] - e[k];
    final tolerance = math.max(15.0, 0.1 * (e[top] - e[start]));
    if (drop > tolerance || s[k] - s[top] > 1000) {
      close(start, top);
      start = -1;
      low = k;
    }
  }
  if (start >= 0) close(start, top);

  if (found.length <= digestMaxClimbs) return found;
  final biggest = [...found]..sort((a, b) => b.gainM.compareTo(a.gainM));
  return biggest.take(digestMaxClimbs).toList()
    ..sort((a, b) => a.startKm.compareTo(b.startKm));
}

/* ------------------------------------------------------- towns and places */

List<DigestTown> _towns(_Line line, List<DigestCandidate> candidates) {
  final byName = <String, ({DigestCandidate c, double along, double off})>{};
  for (final c in candidates) {
    final reach = digestTownReachM[c.kind];
    if (reach == null || c.name.trim().isEmpty) continue;
    final hit = line.nearest(c.position, reach);
    if (hit == null) continue;
    final seen = byName[c.name];
    if (seen != null && seen.off <= hit.off) continue;
    byName[c.name] = (c: c, along: hit.along, off: hit.off);
  }
  final rank = digestTownReachM.keys.toList();
  final kept = _spread(
    byName.values.toList(),
    digestMaxTowns,
    line.length,
    along: (t) => t.along,
    better: (a, b) {
      final byKind = rank.indexOf(a.c.kind).compareTo(rank.indexOf(b.c.kind));
      return byKind != 0 ? byKind : a.off.compareTo(b.off);
    },
  )..sort((a, b) => a.along.compareTo(b.along));
  return [
    for (final t in kept)
      DigestTown(
        name: _clip(t.c.name),
        kind: t.c.kind,
        km: _round(t.along / 1000, 1),
        at: _point(t.c.position),
      ),
  ];
}

List<DigestPlace> _places(_Line line, List<DigestCandidate> candidates) {
  final near = <({DigestCandidate c, double along, double off})>[];
  for (final c in candidates) {
    if (!digestPlaceKinds.contains(c.kind)) continue;
    final hit = line.nearest(c.position, digestPlaceReachM);
    if (hit == null) continue;
    near.add((c: c, along: hit.along, off: hit.off));
  }
  // The same café mapped twice, or three taps on one square, are one stop:
  // the nearer to the route stays.
  near.sort((a, b) => a.off.compareTo(b.off));
  final unique = <({DigestCandidate c, double along, double off})>[];
  for (final p in near) {
    final twin = unique.any(
      (u) =>
          u.c.kind == p.c.kind &&
          u.c.name == p.c.name &&
          haversineMeters(u.c.position, p.c.position) <
              (p.c.name.isEmpty ? 150 : 250),
    );
    if (!twin) unique.add(p);
  }

  // Within one part of the route every kind gets its turn before a second
  // café does; the more useful kind first, then the nearer.
  final kept = _spread(
    unique,
    digestMaxPlaces,
    line.length,
    along: (p) => p.along,
    group: (p) => p.c.kind,
    better: (a, b) {
      final byKind = digestPlaceKinds
          .indexOf(a.c.kind)
          .compareTo(digestPlaceKinds.indexOf(b.c.kind));
      return byKind != 0 ? byKind : a.off.compareTo(b.off);
    },
  )..sort((a, b) => a.along.compareTo(b.along));

  return [
    for (var i = 0; i < kept.length; i++)
      DigestPlace(
        id: 'p${i + 1}',
        kind: kept[i].c.kind,
        name: kept[i].c.name.trim().isEmpty ? null : _clip(kept[i].c.name),
        km: _round(kept[i].along / 1000, 1),
        offM: kept[i].off.roundToDouble(),
        at: _point(kept[i].c.position),
      ),
  ];
}

/// At most [cap] of [items], spread along the route: the route is cut into
/// parts, each part's items are ranked by [better] — and, with [group], the
/// best of every group before the second of any — and the parts take turns
/// handing over their best until [cap] are chosen.
List<T> _spread<T>(
  List<T> items,
  int cap,
  double length, {
  required double Function(T) along,
  required int Function(T, T) better,
  Object? Function(T)? group,
}) {
  if (items.length <= cap) return [...items];
  final parts = math.max(1, (cap / 4).ceil());
  final buckets = List<List<T>>.generate(parts, (_) => <T>[]);
  for (final item in items) {
    final i = length <= 0
        ? 0
        : (along(item) / length * parts).floor().clamp(0, parts - 1);
    buckets[i].add(item);
  }
  for (final b in buckets) {
    b.sort(better);
    if (group == null) continue;
    final turn = <T, int>{};
    final taken = <Object?, int>{};
    for (final item in b) {
      final g = group(item);
      turn[item] = taken[g] = (taken[g] ?? -1) + 1;
    }
    // A stable sort by turn keeps [better]'s order within each turn.
    final ranked = [for (var i = 0; i < b.length; i++) (i, b[i])]
      ..sort((x, y) {
        final byTurn = turn[x.$2]!.compareTo(turn[y.$2]!);
        return byTurn != 0 ? byTurn : x.$1.compareTo(y.$1);
      });
    b
      ..clear()
      ..addAll([for (final r in ranked) r.$2]);
  }
  final chosen = <T>[];
  for (var round = 0; chosen.length < cap; round++) {
    var any = false;
    for (final b in buckets) {
      if (round < b.length && chosen.length < cap) {
        chosen.add(b[round]);
        any = true;
      }
    }
    if (!any) break;
  }
  return chosen;
}

/* ------------------------------------------------------------------- help */

/// A gradient as the relay takes it: the elevation model has the odd cliff.
double _grade(double v) => _round(v.clamp(-60, 60).toDouble(), 1);

double _round(double v, int decimals) {
  final f = math.pow(10, decimals);
  return (v * f).round() / f;
}

DigestPoint _point(LatLng p) =>
    DigestPoint(lat: _round(p.lat, 5), lon: _round(p.lon, 5));

/// A name as the relay takes it: at most 120 characters.
String _clip(String name) {
  final trimmed = name.trim();
  return trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120);
}
