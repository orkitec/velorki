import 'dart:io';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

void main() {
  test('exports a version', () {
    expect(packageVersion, isNotEmpty);
  });

  test('upstreamVersion is the pinned BRouter tag of the repository', () {
    expect(upstreamVersion, 'v1.7.10');
    final pinned = File('../../../brouter/UPSTREAM_VERSION');
    if (pinned.existsSync()) {
      expect(pinned.readAsStringSync().trim(), upstreamVersion);
    }
  });
}
