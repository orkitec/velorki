/// How long the search box may take on a real, city-sized gazetteer.
///
/// Not a benchmark and not a phone: these are the ceilings that catch a
/// regression on a GitHub runner — an index that stopped being used, a
/// prepared statement that turned into a table scan, a spelling pass that
/// started walking the whole vocabulary. Generous on purpose.
///
///     flutter test test/perf/gazetteer_perf_test.dart \
///       --dart-define=GAZETTEER_PERF_FILE=/path/to/W75_N40.gaz
///
/// Skipped when `GAZETTEER_PERF_FILE` is unset. It is read from the
/// `--dart-define` first and from the process environment second, so
/// `GAZETTEER_PERF_FILE=... flutter test ...` works too; the define is what
/// `.github/workflows/gazetteer-perf.yml` passes. The nightly job points it at
/// New York (`W75_N40.gaz`, 89 MB); locally the Madeira fixture
/// (`../tools/gazetteer/fixtures/W20_N30.gaz`, 1.5 MB) works as a smoke test,
/// since only the timings are asserted, never the number of rows.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Ceilings, measured on `ubuntu-latest`.
const Duration _maxMedianPrefix = Duration(milliseconds: 80);
const Duration _maxKindSearch = Duration(milliseconds: 150);
const Duration _maxTypoPath = Duration(milliseconds: 1500);

/// What a rider types: two fragments, a street, a landmark, an address and a
/// kind word. Fixed, so a number means the same thing from run to run.
const List<String> _prefixQueries = <String>[
  'bro',
  'west 4',
  'broadway',
  'central park',
  '410 w 42nd',
  'bakery',
];

/// How many timed prefix queries the median is taken over.
const int _prefixSamples = 20;

/// Times Square. The kind search is a bounding box around a point, so it wants
/// somewhere dense.
const LatLng _manhattan = LatLng(40.7580, -73.9855);

/// Funchal, for the Madeira fixture — the same measurement over the only city
/// that file has.
const LatLng _funchal = LatLng(32.6500, -16.9100);

const String _perfFileDefine = String.fromEnvironment('GAZETTEER_PERF_FILE');

String? _perfFile() {
  if (_perfFileDefine.isNotEmpty) return _perfFileDefine;
  final fromEnv = Platform.environment['GAZETTEER_PERF_FILE'];
  return (fromEnv == null || fromEnv.isEmpty) ? null : fromEnv;
}

void main() {
  final source = _perfFile();
  if (source == null) {
    test('gazetteer performance', () {}, skip: _skipReason);
    return;
  }
  if (!File(source).existsSync()) {
    test('gazetteer performance', () {}, skip: 'no gazetteer at $source');
    return;
  }
  _perfTests(source);
}

const String _skipReason =
    'set GAZETTEER_PERF_FILE to a <TILE>.gaz file, e.g. '
    '--dart-define=GAZETTEER_PERF_FILE=\$PWD/../tools/gazetteer/fixtures/W20_N30.gaz';

void _perfTests(String source) {
  // The store scans a directory for *.gaz and takes the tile name from the
  // file name, so the file is linked into a temp directory under its own name.
  final tile = p.basenameWithoutExtension(source);

  late Directory root;
  late GazetteerStore store;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('velorki-gaz-perf');
    final target = p.join(root.path, '$tile.gaz');
    final absolute = File(source).absolute.path;
    try {
      Link(target).createSync(absolute);
    } on FileSystemException {
      File(absolute).copySync(target);
    }
    store = GazetteerStore(root);
    await store.refresh();
    expect(
      store.tiles,
      contains(tile),
      reason: '$source did not open as a gazetteer',
    );

    // Warm up: the first query opens the FTS index, prepares the statements
    // and pulls the pages off disk, which is not what is being measured.
    for (final text in _prefixQueries) {
      await store.search(text, near: _centre(tile));
    }
    await store.search('toilets', near: _centre(tile));
  });

  tearDownAll(() {
    store.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('a prefix query stays interactive', () async {
    final centre = _centre(tile);
    final samples = <Duration>[];
    final watch = Stopwatch();
    for (var i = 0; i < _prefixSamples; i++) {
      final text = _prefixQueries[i % _prefixQueries.length];
      watch
        ..reset()
        ..start();
      await store.search(text, near: centre);
      watch.stop();
      samples.add(watch.elapsed);
    }
    final median = _median(samples);
    _report('prefix query (median of $_prefixSamples)', median);
    _report('prefix query (slowest)', samples.reduce(_longer));

    expect(
      median,
      lessThan(_maxMedianPrefix),
      reason: 'median prefix query on $tile was ${_ms(median)}',
    );
  });

  test('a kind search stays interactive', () async {
    final watch = Stopwatch()..start();
    final found = await store.search('toilets', near: _centre(tile));
    watch.stop();
    _report('kind search "toilets" (${found.length} rows)', watch.elapsed);

    expect(
      watch.elapsed,
      lessThan(_maxKindSearch),
      reason: 'kind search on $tile took ${_ms(watch.elapsed)}',
    );
  });

  test('a mistyped query is corrected in time', () async {
    // Nothing matches, so the store walks the index vocabulary and runs the
    // query again with the words it guessed at: the slowest path there is.
    final watch = Stopwatch()..start();
    final answer = await store.lookup('brooklyyn', near: _centre(tile));
    watch.stop();
    _report(
      'typo path "brooklyyn" (${answer.correctedQuery ?? 'no correction'})',
      watch.elapsed,
    );

    expect(
      watch.elapsed,
      lessThan(_maxTypoPath),
      reason: 'the spelling pass on $tile took ${_ms(watch.elapsed)}',
    );
  });

  test('the file under test actually answers', () async {
    // The timings above are meaningless against a file that finds nothing, so
    // one query per known tile proves the index is real. Any other tile is
    // only timed.
    final probe = _probe(tile);
    if (probe == null) return;
    final found = await store.search(probe, near: _centre(tile));
    expect(
      found,
      isNotEmpty,
      reason: '"$probe" found nothing in $tile; is the file complete?',
    );
    expect(found.first, isA<SearchResult>());
  });
}

/// Where the kind search looks, for the tiles this test knows.
LatLng _centre(String tile) => switch (tile) {
  'W20_N30' => _funchal,
  _ => _manhattan,
};

/// A query that must find something, for the tiles this test knows.
String? _probe(String tile) => switch (tile) {
  'W75_N40' => 'broadway',
  'W20_N30' => 'funchal',
  _ => null,
};

Duration _median(List<Duration> samples) {
  final sorted = samples.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : Duration(
          microseconds:
              (sorted[middle - 1].inMicroseconds +
                  sorted[middle].inMicroseconds) ~/
              2,
        );
}

Duration _longer(Duration a, Duration b) => a > b ? a : b;

String _ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms';

/// One line per measurement, on stdout. `gazetteer-perf.yml` lifts every line
/// with this prefix into the job's step summary.
void _report(String what, Duration took) {
  // ignore: avoid_print
  print('GAZPERF | $what | ${_ms(took)}');
}
