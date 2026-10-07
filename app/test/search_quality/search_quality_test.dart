/// How well the on-device search finds what a rider meant.
///
/// Runs the real search stack — [GazetteerStore], the same query building,
/// spelling pass and ranking the search field uses — over real `.gaz` files
/// against the test set in `tools/gazetteer/testset/`: the cases
/// `testset.py` generated from each tile (a sampled row, mistyped one way,
/// tagged with that way), the hand-written ones (`handwritten.json`, one or
/// two addresses and landmarks per country and address format) and the few
/// adopted from public geocoder test suites (`public.json`). For every case
/// the query is run with the case's `near` as the rider's position and the
/// rank of the expected row in the ten results is recorded.
///
///     flutter test test/search_quality \
///       --dart-define=VELORKI_GAZ_DIR=$HOME/.cache/velorki-tiles/gaz
///
/// Skipped when `VELORKI_GAZ_DIR` is unset; read from the `--dart-define`
/// first and the process environment second, like `GAZETTEER_PERF_FILE` in
/// `test/perf`. Every `<TILE>.gaz` in the directory is scored on its own, with
/// only that file open, over the cases tagged with its tile; a tile with no
/// cases is skipped and a case whose tile is not in the directory is not
/// counted.
///
/// The score is per tile and per corruption kind: how often the expected row
/// is the first result, in the first three, in the ten shown, and its mean
/// rank when it is there at all. A row is "the expected one" when its name
/// folds to the same text (`foldSearchTerm`, the index's own folding) and it
/// lies within [_pointToleranceMeters] of the expected point — or within
/// [_streetToleranceMeters] for a street, because a street is one row per
/// place it passes through and a hand-written case cannot say which; a case
/// may set its own `tolerance_m`. Ids are not compared: a rebuilt tile
/// renumbers everything.
///
/// A low score never fails the test — the point is the baseline and the
/// difference a change makes — only an infrastructure error does: a file that
/// does not open, a test set that does not parse, a query that throws. The
/// table goes to stdout, one `SEARCHQ |` line per row, and the full result,
/// every case with its rank, to `build/search_quality/<TILE>.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/fuzzy.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Where the test set lives, relative to `app/`, which is where `flutter test`
/// runs.
const String _testsetDir = '../tools/gazetteer/testset';

/// Where the per-tile results are written, relative to `app/`.
const String _outDir = 'build/search_quality';

/// How many results the search field shows, and so how far down a hit counts.
const int _limit = 10;

/// How close a place or a POI has to be to the expected point.
const double _pointToleranceMeters = 300;

/// How close a street has to be: a long street is several rows, one per place
/// it runs through, and the hand-written cases name the street, not the row.
const double _streetToleranceMeters = 3000;

const String _gazDirDefine = String.fromEnvironment('VELORKI_GAZ_DIR');

String? _gazDir() {
  if (_gazDirDefine.isNotEmpty) return _gazDirDefine;
  final fromEnv = Platform.environment['VELORKI_GAZ_DIR'];
  return (fromEnv == null || fromEnv.isEmpty) ? null : fromEnv;
}

const String _skipReason =
    'set VELORKI_GAZ_DIR to a directory of <TILE>.gaz files, e.g. '
    '--dart-define=VELORKI_GAZ_DIR=\$HOME/.cache/velorki-tiles/gaz';

void main() {
  final dir = _gazDir();
  if (dir == null) {
    test('search quality', () {}, skip: _skipReason);
    return;
  }
  if (!Directory(dir).existsSync()) {
    test('search quality', () {}, skip: 'no directory at $dir');
    return;
  }

  // Nothing here may call expect(): main runs outside any test. A test set
  // that does not load throws, which fails the file with the message.
  final cases = _loadCases();
  final tiles =
      Directory(dir)
          .listSync(followLinks: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.gaz'))
          .map((f) => f.path)
          .toList()
        ..sort();
  if (tiles.isEmpty) {
    test('search quality', () => fail('no .gaz files in $dir'));
    return;
  }

  for (final path in tiles) {
    final tile = p.basenameWithoutExtension(path);
    final own = cases.where((c) => c.tile == tile).toList();
    if (own.isEmpty) {
      test(tile, () {}, skip: 'no cases for $tile');
      continue;
    }
    test(
      '$tile (${own.length} cases)',
      () => _scoreTile(path, tile, own),
      timeout: const Timeout(Duration(minutes: 15)),
    );
  }
}

/// One query with the row it should find.
class _Case {
  const _Case({
    required this.query,
    required this.kind,
    required this.group,
    required this.tile,
    required this.near,
    required this.expectedName,
    required this.expected,
    required this.table,
    required this.toleranceMeters,
    this.source,
  });

  final String query;
  final String kind;

  /// Which file the case came from: `generated`, `handwritten` or `public`.
  final String group;
  final String tile;
  final LatLng? near;
  final String expectedName;
  final LatLng expected;
  final String? table;
  final double toleranceMeters;
  final String? source;

  factory _Case.fromJson(Map<String, Object?> json, String group, String file) {
    final expected = json['expected'];
    if (expected is! Map<String, Object?>) {
      throw FormatException('case without expected in $file: $json');
    }
    final table = expected['table']?.toString();
    final near = json['near'];
    final tolerance = json['tolerance_m'];
    return _Case(
      query: _string(json['query'], 'query', file),
      kind: _string(json['kind'], 'kind', file),
      group: group,
      tile: _string(json['tile'], 'tile', file),
      near: near is Map<String, Object?> ? _point(near, file) : null,
      expectedName: _string(expected['name'], 'expected.name', file),
      expected: _point(expected, file),
      table: table,
      toleranceMeters: tolerance is num
          ? tolerance.toDouble()
          : table == 'streets'
          ? _streetToleranceMeters
          : _pointToleranceMeters,
      source: json['source']?.toString(),
    );
  }

  static String _string(Object? value, String what, String file) {
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('a case in $file has no $what');
  }

  static LatLng _point(Map<String, Object?> json, String file) {
    final lat = json['lat'];
    final lon = json['lon'];
    if (lat is num && lon is num) return LatLng(lat.toDouble(), lon.toDouble());
    throw FormatException('a case in $file has no lat/lon: $json');
  }
}

/// Every case of every file under `tools/gazetteer/testset/`.
List<_Case> _loadCases() {
  final root = Directory(_testsetDir);
  if (!root.existsSync()) {
    throw StateError('no test set at ${root.absolute.path}');
  }
  final cases = <_Case>[];
  void read(File file, String group) {
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      throw FormatException('${file.path} is not JSON: $e');
    }
    if (decoded is! Map<String, Object?> || decoded['cases'] is! List) {
      throw FormatException('${file.path} has no "cases" list');
    }
    for (final entry in decoded['cases'] as List) {
      if (entry is! Map<String, Object?>) {
        throw FormatException('${file.path}: bad case $entry');
      }
      cases.add(_Case.fromJson(entry, group, file.path));
    }
  }

  for (final file in root.listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    read(file, p.basenameWithoutExtension(file.path));
  }
  final generated = Directory(p.join(root.path, 'generated'));
  if (generated.existsSync()) {
    for (final file in generated.listSync().whereType<File>()) {
      if (file.path.endsWith('.json')) read(file, 'generated');
    }
  }
  if (cases.isEmpty) throw StateError('the test set is empty');
  return cases;
}

/// What one query did.
class _Outcome {
  const _Outcome({
    required this.c,
    required this.rank,
    required this.first,
    required this.corrected,
    required this.took,
  });

  final _Case c;

  /// 1-based position of the expected row, or `null` when it was not shown.
  final int? rank;
  final String? first;
  final String? corrected;
  final Duration took;
}

Future<void> _scoreTile(String path, String tile, List<_Case> cases) async {
  // The store scans a directory for *.gaz and takes the tile name from the
  // file name, so one file is linked into a temp directory of its own: only
  // this tile answers, whatever else the directory holds.
  final root = Directory.systemTemp.createTempSync('velorki-searchq');
  final store = GazetteerStore(root);
  try {
    final target = p.join(root.path, '$tile.gaz');
    final absolute = File(path).absolute.resolveSymbolicLinksSync();
    try {
      Link(target).createSync(absolute);
    } on FileSystemException {
      File(absolute).copySync(target);
    }
    await store.refresh();
    expect(store.tiles, [tile], reason: '$path did not open as a gazetteer');

    final outcomes = <_Outcome>[];
    final watch = Stopwatch();
    for (final c in cases) {
      watch
        ..reset()
        ..start();
      final GazetteerSearch found;
      try {
        found = await store.lookup(c.query, near: c.near, limit: _limit);
      } on Object catch (e, st) {
        fail('"${c.query}" (${c.kind}) threw on $tile: $e\n$st');
      }
      watch.stop();
      int? rank;
      for (var i = 0; i < found.results.length; i++) {
        if (_matches(found.results[i], c)) {
          rank = i + 1;
          break;
        }
      }
      outcomes.add(
        _Outcome(
          c: c,
          rank: rank,
          first: found.results.isEmpty ? null : found.results.first.name,
          corrected: found.correctedQuery,
          took: watch.elapsed,
        ),
      );
    }
    _report(tile, File(absolute).lengthSync(), outcomes);
  } finally {
    store.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

bool _matches(SearchResult result, _Case c) {
  if (_fold(result.name) != _fold(c.expectedName)) return false;
  return haversineMeters(result.position, c.expected) <= c.toleranceMeters;
}

String _fold(String name) => foldSearchTerm(name).trim();

/// A row of the table: one kind (or group, or the whole tile).
class _Score {
  int n = 0;
  int top1 = 0;
  int top3 = 0;
  int top10 = 0;
  int rankSum = 0;

  void add(int? rank) {
    n++;
    if (rank == null) return;
    rankSum += rank;
    top10++;
    if (rank <= 3) top3++;
    if (rank == 1) top1++;
  }

  double? get meanRank => top10 == 0 ? null : rankSum / top10;

  Map<String, Object?> toJson() => <String, Object?>{
    'n': n,
    'top1': top1,
    'top3': top3,
    'top10': top10,
    'mean_rank': meanRank,
  };
}

void _report(String tile, int bytes, List<_Outcome> outcomes) {
  final byKind = <String, _Score>{};
  final byGroup = <String, _Score>{};
  final all = _Score();
  var elapsed = Duration.zero;
  for (final o in outcomes) {
    byKind.putIfAbsent(o.c.kind, _Score.new).add(o.rank);
    byGroup.putIfAbsent(o.c.group, _Score.new).add(o.rank);
    all.add(o.rank);
    elapsed += o.took;
  }

  final times = <int>[for (final o in outcomes) o.took.inMicroseconds]..sort();
  String at(double share) => times.isEmpty
      ? '-'
      : (times[((times.length - 1) * share).round()] / 1000).toStringAsFixed(1);

  String pct(int part, int whole) =>
      whole == 0 ? '   -' : '${(100 * part / whole).round()}%'.padLeft(4);
  String row(String label, _Score s) =>
      'SEARCHQ | $tile | ${label.padRight(16)} | ${'${s.n}'.padLeft(4)} | '
      '${pct(s.top1, s.n)} | ${pct(s.top3, s.n)} | ${pct(s.top10, s.n)} | '
      '${s.meanRank?.toStringAsFixed(2).padLeft(5) ?? '    -'}';

  final lines = <String>[
    'SEARCHQ | $tile | ${(bytes / 1e6).toStringAsFixed(1)} MB, '
        '${outcomes.length} cases in ${elapsed.inMilliseconds} ms '
        '(median ${at(0.5)} ms, p90 ${at(0.9)} ms, max ${at(1)} ms)',
    'SEARCHQ | tile    | kind             |    n | top1 | top3 | top10 | rank',
    for (final kind in byKind.keys.toList()..sort()) row(kind, byKind[kind]!),
    for (final group in byGroup.keys.toList()..sort())
      row('[$group]', byGroup[group]!),
    row('[all]', all),
  ];
  for (final line in lines) {
    // ignore: avoid_print
    print(line);
  }

  final out = File(p.join(_outDir, '$tile.json'))
    ..parent.createSync(recursive: true);
  out.writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(<String, Object?>{
      'tile': tile,
      'gaz_bytes': bytes,
      'cases': outcomes.length,
      'elapsed_ms': elapsed.inMilliseconds,
      'all': all.toJson(),
      'kinds': <String, Object?>{
        for (final kind in byKind.keys.toList()..sort())
          kind: byKind[kind]!.toJson(),
      },
      'groups': <String, Object?>{
        for (final group in byGroup.keys.toList()..sort())
          group: byGroup[group]!.toJson(),
      },
      'results': <Object?>[
        for (final o in outcomes)
          <String, Object?>{
            'query': o.c.query,
            'kind': o.c.kind,
            'group': o.c.group,
            'expected': o.c.expectedName,
            'rank': o.rank,
            'first': o.first,
            'corrected': ?o.corrected,
            'ms': o.took.inMilliseconds,
          },
      ],
    }),
  );
}
