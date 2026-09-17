import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/files/backup_exclusion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(backupChannelName);
  final directory = Directory('/tmp/velorki-backup-test/brouter');

  late List<MethodCall> calls;

  setUp(() => calls = <MethodCall>[]);

  /// Answers the channel with [handler], recording every call.
  void answerWith(Future<Object?> Function(MethodCall call) handler) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  void runningOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  /// Everything [debugPrint] was handed while [body] ran.
  Future<List<String>> printsOf(Future<void> Function() body) async {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      await body();
    } finally {
      debugPrint = previous;
    }
    return lines;
  }

  test('asks the platform to exclude the directory on iOS', () async {
    runningOn(TargetPlatform.iOS);
    answerWith((call) async => true);

    expect(
      await const BackupExclusion(channel: channel).exclude(directory),
      isTrue,
    );
    expect(calls, hasLength(1));
    expect(calls.single.method, excludeFromBackupMethod);
    expect(calls.single.arguments, directory.path);
  });

  test('reports the platform saying there was nothing to exclude', () async {
    runningOn(TargetPlatform.iOS);
    answerWith((call) async => false);

    expect(
      await const BackupExclusion(channel: channel).exclude(directory),
      isFalse,
    );
  });

  test('does not touch the channel on Android', () async {
    runningOn(TargetPlatform.android);
    answerWith((call) async => true);

    expect(
      await const BackupExclusion(channel: channel).exclude(directory),
      isTrue,
    );
    expect(calls, isEmpty);
  });

  test('tolerates a build without the channel', () async {
    runningOn(TargetPlatform.iOS);
    // No mock handler: invoking throws MissingPluginException.

    expect(
      await const BackupExclusion(channel: channel).exclude(directory),
      isTrue,
    );
  });

  test('logs a FlutterError and reports failure', () async {
    runningOn(TargetPlatform.iOS);
    answerWith(
      (call) async => throw PlatformException(
        code: 'exclude_failed',
        message: 'could not exclude ${directory.path} from the backup',
        details: 'The operation could not be completed.',
      ),
    );

    late bool excluded;
    final lines = await printsOf(() async {
      excluded = await const BackupExclusion(channel: channel)
          .exclude(directory);
    });

    expect(excluded, isFalse);
    expect(lines, hasLength(1));
    expect(lines.single, contains(directory.path));
    expect(lines.single, contains('exclude_failed'));
  });
}
