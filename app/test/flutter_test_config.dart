import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/shell_layout.dart';

/// Runs every widget test on the layout of a phone held upright, the one
/// they were written for: the default test screen, 800 by 600, is wider than
/// tall and would get the rail. The tests of the rail clear the override.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => debugShellLayoutOverride = ShellLayout.bottomBar);
  tearDown(() => debugShellLayoutOverride = null);
  await testMain();
}
