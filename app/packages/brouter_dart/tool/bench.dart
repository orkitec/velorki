// Routing benchmark for track R5: routes a fixed set of corpus cases plus two
// long cross-tile routes N times warm, directly (`BRouter`) and through the
// `RoutingWorker` isolate, and prints medians and RSS.
//
//   dart run tool/bench.dart [--runs N] [--only <id prefix>] [--no-worker]
//       [--memoryclass N]
//
// Needs the two rd5 tiles (`BROUTER_SEGMENTS_DIR`, default the oracle cache)
// and the profiles (`BROUTER_PROFILES_DIR`, default `brouter/profiles`).

import 'dart:io';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:brouter_dart/isolate.dart';

final Directory segmentsDir = Directory(
  Platform.environment['BROUTER_SEGMENTS_DIR'] ??
      '../../../tools/brouter-oracle/.cache/segments4',
);
final Directory profilesDir = Directory(
  Platform.environment['BROUTER_PROFILES_DIR'] ?? '../../../brouter/profiles',
);

class BenchCase {
  const BenchCase(this.id, this.what, this.query);

  final String id;
  final String what;
  final String query;
}

const List<BenchCase> cases = [
  BenchCase(
    'pair-000',
    'short pair, trekking, 3.6 km, Madeira',
    'lonlats=-16.863901,32.647377%7C-16.887019,32.651685&profile=trekking&alternativeidx=0&format=geojson',
  ),
  BenchCase(
    'pair-005',
    'longest corpus pair, trekking alt 1, 7.6 km, Iceland',
    'lonlats=-22.117246,64.025978%7C-22.080427,64.033481&profile=trekking&alternativeidx=1&format=geojson',
  ),
  BenchCase(
    'triple-031',
    'longest triple, fastbike alt 3, 14.5 km, Iceland',
    'lonlats=-22.185232,64.011698%7C-22.117246,64.025978%7C-22.080427,64.033481&profile=fastbike&alternativeidx=3&format=geojson',
  ),
  BenchCase(
    'nogo-000',
    'nogo, trekking, 5.9 km, Madeira',
    'lonlats=-16.839044,32.655749%7C-16.80416,32.670006&nogos=-16.821602,32.662878,120&profile=trekking&alternativeidx=0&format=geojson',
  ),
  BenchCase(
    'roundtrip-000',
    'round trip, trekking, 5 points, 9.9 km, Madeira',
    'lonlats=-16.9085,32.6485&profile=trekking&format=geojson&engineMode=4&roundTripDistance=1200&direction=0&roundTripPoints=5',
  ),
  BenchCase(
    'roundtrip-003',
    'longest round trip, gravel, 20 km, Iceland',
    'lonlats=-21.9414,64.0671&profile=gravel&format=geojson&engineMode=4&roundTripDistance=3000&direction=90&roundTripPoints=5',
  ),
  BenchCase(
    'madeira-long',
    'Funchal -> Porto Moniz, trekking, across Madeira (~60 km)',
    'lonlats=-16.9066,32.6669%7C-17.1700,32.8667&profile=trekking&alternativeidx=0&format=geojson',
  ),
  BenchCase(
    'iceland-long',
    'Reykjavik -> Keflavik, trekking (~47 km)',
    'lonlats=-21.9426,64.1466%7C-22.5600,63.9950&profile=trekking&alternativeidx=0&format=geojson',
  ),
];

int _median(List<int> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

Future<void> main(List<String> args) async {
  var runs = 5;
  String? only;
  var worker = true;
  var memoryclass = 128;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--runs':
        runs = int.parse(args[++i]);
      case '--only':
        only = args[++i];
      case '--no-worker':
        worker = false;
      case '--memoryclass':
        memoryclass = int.parse(args[++i]);
    }
  }
  final selected = [
    for (final c in cases)
      if (only == null || c.id.startsWith(only)) c,
  ];

  final router = BRouter(segmentsDir: segmentsDir, profilesDir: profilesDir)
    ..memoryclass = memoryclass;

  stdout.writeln(
    'brouter_dart bench: $runs warm runs per case, memoryclass=$memoryclass, '
    'segments=${segmentsDir.path}',
  );
  stdout.writeln('rss at start: ${_mb(ProcessInfo.currentRss)}');
  stdout.writeln();
  stdout.writeln(
    '${'case'.padRight(14)} ${'links'.padLeft(8)} ${'length'.padLeft(8)} '
    '${'direct ms'.padLeft(10)} ${'min'.padLeft(6)} ${'worker ms'.padLeft(10)}',
  );

  final results = <String, Map<String, Object>>{};
  for (final c in selected) {
    // one cold run, not timed, to load the profile and touch the tiles
    var links = 0;
    router.progressListener = (l, o) => links = l;
    String body;
    try {
      body = await router.routeQuery(c.query);
    } on RoutingException catch (e) {
      stdout.writeln('${c.id.padRight(14)} ERROR ${e.message}');
      continue;
    }
    final result = RoutingResult.parse(body);
    final times = <int>[];
    for (var r = 0; r < runs; r++) {
      final sw = Stopwatch()..start();
      final b = await router.routeQuery(c.query);
      sw.stop();
      if (b != body) {
        stdout.writeln('${c.id}: non-deterministic output on run $r');
      }
      times.add(sw.elapsedMicroseconds);
    }
    final linksProcessed = router.currentEngine?.getLinksProcessed() ?? links;
    results[c.id] = {
      'direct': _median(times),
      'min': times.reduce((a, b) => a < b ? a : b),
      'links': linksProcessed,
      'length': result.trackLength,
      'body': body,
    };
    stdout.writeln(
      '${c.id.padRight(14)} ${linksProcessed.toString().padLeft(8)} '
      '${result.trackLength.toString().padLeft(8)} '
      '${(_median(times) / 1000).toStringAsFixed(1).padLeft(10)} '
      '${(times.reduce((a, b) => a < b ? a : b) / 1000).toStringAsFixed(1).padLeft(6)}',
    );
  }
  stdout.writeln();
  stdout.writeln(
    'direct: rss now ${_mb(ProcessInfo.currentRss)}, peak ${_mb(ProcessInfo.maxRss)}',
  );

  if (worker) {
    stdout.writeln();
    final w = await RoutingWorker.spawn(
      segmentsDir: segmentsDir,
      profilesDir: profilesDir,
      memoryclass: memoryclass,
    );
    for (final c in selected) {
      final r = results[c.id];
      if (r == null) continue;
      await w.routeQuery(c.query);
      final times = <int>[];
      for (var i = 0; i < runs; i++) {
        final sw = Stopwatch()..start();
        final b = await w.routeQuery(c.query);
        sw.stop();
        if (b != r['body']) {
          stdout.writeln('${c.id}: worker output differs from direct');
        }
        times.add(sw.elapsedMicroseconds);
      }
      r['worker'] = _median(times);
      stdout.writeln(
        '${c.id.padRight(14)} ${'-'.padLeft(8)} ${'-'.padLeft(8)} '
        '${((r['direct'] as int) / 1000).toStringAsFixed(1).padLeft(10)} '
        '${'-'.padLeft(6)} '
        '${(_median(times) / 1000).toStringAsFixed(1).padLeft(10)}',
      );
    }
    await w.dispose();
    stdout.writeln();
    stdout.writeln(
      'with worker: rss now ${_mb(ProcessInfo.currentRss)}, peak ${_mb(ProcessInfo.maxRss)}',
    );
  }

  stdout.writeln();
  stdout.writeln('| Case | Links | Length m | Direct ms | Worker ms |');
  stdout.writeln('|---|---:|---:|---:|---:|');
  for (final c in selected) {
    final r = results[c.id];
    if (r == null) continue;
    final wk = r['worker'];
    stdout.writeln(
      '| ${c.id} (${c.what}) | ${r['links']} | ${r['length']} | '
      '${((r['direct'] as int) / 1000).toStringAsFixed(0)} | '
      '${wk == null ? '-' : ((wk as int) / 1000).toStringAsFixed(0)} |',
    );
  }
}
