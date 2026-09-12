// The L3 corpus of tools/brouter-oracle (200 recorded requests and their
// verbatim GeoJSON responses from the real 1.7.10 server).

import 'dart:convert';
import 'dart:io';

import 'package:brouter_dart/brouter_dart.dart';

import 'mapaccess_support.dart';

final Directory oracleDir = Directory(
  Platform.environment['BROUTER_ORACLE_DIR'] ?? '../../../tools/brouter-oracle',
);

class CorpusCase {
  CorpusCase(this.id, this.kind, this.profile, this.query, this.responseFile);

  final String id;
  final String kind;
  final String profile;
  final String query;
  final File responseFile;
}

List<CorpusCase> loadCorpus() {
  final index = jsonDecode(
    File('${oracleDir.path}/corpus/index.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final requests = jsonDecode(
    File('${oracleDir.path}/corpus/requests.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final queries = <String, String>{
    for (final c in (requests['cases'] as List).cast<Map<String, dynamic>>())
      c['id'] as String: c['query'] as String,
  };
  return [
    for (final c in (index['cases'] as List).cast<Map<String, dynamic>>())
      CorpusCase(
        c['id'] as String,
        c['kind'] as String,
        c['profile'] as String,
        queries[c['id'] as String] ?? c['query'] as String,
        File('${oracleDir.path}/corpus/${c['response']}'),
      ),
  ];
}

BRouter oracleRouter() =>
    BRouter(segmentsDir: segmentsDir, profilesDir: profilesDir);

/// The first differing byte offset with a context snippet, or null.
String? firstDifference(List<int> actual, List<int> expected) {
  final n = actual.length < expected.length ? actual.length : expected.length;
  for (var i = 0; i < n; i++) {
    if (actual[i] != expected[i]) return _snippet(i, actual, expected);
  }
  if (actual.length != expected.length) return _snippet(n, actual, expected);
  return null;
}

String _snippet(int i, List<int> actual, List<int> expected) {
  String around(List<int> b) {
    final s = i - 60 < 0 ? 0 : i - 60;
    final e = i + 60 > b.length ? b.length : i + 60;
    return utf8
        .decode(b.sublist(s, e), allowMalformed: true)
        .replaceAll('\n', '\\n');
  }

  return 'first difference at byte $i (actual ${actual.length} bytes, expected ${expected.length})\n'
      '  expected: ...${around(expected)}...\n'
      '  actual:   ...${around(actual)}...';
}
