/// Asking the host for a picture of the simulator screen.
///
/// A store screenshot has to show the whole screen as a rider sees it: the
/// status bar, and the map, which is a platform view the in-test screenshot
/// cannot capture. So the host takes it with `xcrun simctl io screenshot`.
/// `tool/store_shutter.py` watches the app's container for
/// `Library/Application Support/itest/shot.txt`, takes the picture it names,
/// and writes the request's token to `shot.ack` beside it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../support/harness.dart';

/// Holds the screen still for [hold], so map tiles and animations are done,
/// then asks for a picture saved as `<name>.png` under the host's output
/// directory and waits until it is taken.
Future<void> takeStoreShot(
  WidgetTester tester,
  String name, {
  Duration hold = const Duration(seconds: 4),
}) async {
  await pumpFor(tester, hold);
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'itest'));
  await dir.create(recursive: true);
  final request = File(p.join(dir.path, 'shot.txt'));
  final ack = File(p.join(dir.path, 'shot.ack'));
  final token = '${DateTime.now().microsecondsSinceEpoch}';
  await request.writeAsString('id=$token\nname=$name\n');
  await waitUntil(
    tester,
    () => ack.existsSync() && ack.readAsStringSync().trim() == token,
    describe: 'tool/store_shutter.py to take $name',
    timeout: const Duration(seconds: 60),
    onTimeout: () => 'is tool/store_shutter.py running?',
  );
  debugPrint('VELORKI_STORE shot $name');
}
