import 'dart:async';

import 'package:velorki_io/src/worker_channel_inline.dart' as inline;
import 'package:velorki_io/src/worker_channel_isolate.dart' as isolate;
import 'package:velorki_io/src/worker_channel_types.dart';
import 'package:test/test.dart';

/// A worker that doubles what it is sent, says when it was told to stop, and
/// stops listening then.
void _doubler(
  Object? init,
  void Function(Object? message) send,
  void Function(void Function(Object? message) onMessage) listen,
  void Function() stop,
) {
  final factor = init! as int;
  listen((message) {
    if (message == 'stop') {
      send('stopped');
      stop();
      return;
    }
    send((message! as int) * factor);
  });
}

typedef _Spawn = Future<WorkerChannel> Function(
  WorkerMain main,
  Object? init,
  void Function(Object? message) onMessage, {
  String? debugName,
});

void main() {
  for (final (name, run) in <(String, Future<int> Function(int Function()))>[
    ('inline', inline.runIsolated),
    ('isolate', isolate.runIsolated),
  ]) {
    test(
      '$name: runIsolated answers later, with the result or the error',
      () async {
        var ran = false;
        final result = run(() {
          ran = true;
          return 6 * 7;
        });
        if (name == 'inline') expect(ran, isFalse);
        expect(await result, 42);
        await expectLater(run(() => throw StateError('no')), throwsStateError);
      },
    );
  }

  // The browser's channel and the phone's, held to the same contract: the
  // RoutingWorker above them cannot tell which one it got.
  for (final (name, spawn) in <(String, _Spawn)>[
    ('inline', inline.spawnWorkerChannel),
    ('isolate', isolate.spawnWorkerChannel),
  ]) {
    group(name, () {
      test('answers in order, as separate events', () async {
        final answers = <Object?>[];
        final done = Completer<void>();
        final channel = await spawn(_doubler, 3, (message) {
          answers.add(message);
          if (answers.length == 3) done.complete();
        });
        channel
          ..send(1)
          ..send(2)
          ..send(5);
        // Nothing is answered synchronously, as with a port.
        expect(answers, isEmpty);
        await done.future;
        expect(answers, <Object?>[3, 6, 15]);
        channel.close();
      });

      test('a closed channel delivers nothing more', () async {
        final answers = <Object?>[];
        final channel = await spawn(_doubler, 2, answers.add);
        channel.send(4);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(answers, <Object?>[8]);
        channel.close();
        channel.send(5);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(answers, <Object?>[8]);
      });
    });
  }

  test('inline: the worker can stop listening', () async {
    final answers = <Object?>[];
    final channel = await inline.spawnWorkerChannel(_doubler, 2, answers.add);
    channel
      ..send('stop')
      ..send(1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(answers, <Object?>['stopped']);
  });
}
