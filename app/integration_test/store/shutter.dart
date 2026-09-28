/// Asking the host for a picture of the simulator screen.
///
/// A store screenshot has to show the whole screen as a rider sees it: the
/// status bar, and the map, which is a platform view the in-test screenshot
/// cannot capture. So the host takes it with `xcrun simctl io screenshot`.
/// `tool/store_shutter.py` watches the app's container for
/// `Library/Application Support/itest/shot.txt`, does what it asks, and writes
/// the request's token to `shot.ack` beside it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../support/harness.dart';

/// Holds the screen still for [hold], so map tiles and animations are done,
/// then asks for a picture saved as `<name>.png` under the host's output
/// directory and waits until it is taken.
///
/// [offline] shows the status bar with no signal at all, for the one picture
/// that is about riding without one.
Future<void> takeStoreShot(
  WidgetTester tester,
  String name, {
  Duration hold = const Duration(seconds: 4),
  bool offline = false,
}) async {
  await pumpFor(tester, hold);
  await _ask(tester, name, <String>[
    'action=shot',
    if (offline) 'status=offline',
  ]);
  debugPrint('VELORKI_STORE shot $name');
}

/// Hands [data] to the host, which saves it as `<name>.json` beside the
/// pictures: figures a slide draws itself, such as the Live Activity's.
Future<void> sendStoreData(
  WidgetTester tester,
  String name,
  Map<String, Object?> data,
) async {
  final dir = await _dir();
  await File(p.join(dir.path, 'data.json')).writeAsString(jsonEncode(data));
  await _ask(tester, name, const <String>['action=data']);
  debugPrint('VELORKI_STORE data $name');
}

Future<Directory> _dir() async {
  final base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, 'itest')).create(recursive: true);
}

Future<void> _ask(WidgetTester tester, String name, List<String> lines) async {
  final dir = await _dir();
  final request = File(p.join(dir.path, 'shot.txt'));
  final ack = File(p.join(dir.path, 'shot.ack'));
  final token = '${DateTime.now().microsecondsSinceEpoch}';
  await request.writeAsString(
    <String>['id=$token', 'name=$name', ...lines, ''].join('\n'),
  );
  await waitUntil(
    tester,
    () => ack.existsSync() && ack.readAsStringSync().trim() == token,
    describe: 'tool/store_shutter.py to take $name',
    timeout: const Duration(seconds: 60),
    onTimeout: () => 'is tool/store_shutter.py running?',
  );
}
