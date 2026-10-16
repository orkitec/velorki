import 'dart:async';
import 'dart:isolate';

import 'worker_channel_types.dart';

export 'worker_channel_types.dart';

/// Starts [main] on an isolate of its own and returns once it listens.
Future<WorkerChannel> spawnWorkerChannel(
  WorkerMain main,
  Object? init,
  void Function(Object? message) onMessage, {
  String? debugName,
}) async {
  final fromWorker = ReceivePort();
  final ready = Completer<SendPort>();
  fromWorker.listen((Object? message) {
    if (!ready.isCompleted && message is SendPort) {
      ready.complete(message);
      return;
    }
    onMessage(message);
  });
  final isolate = await Isolate.spawn<(SendPort, WorkerMain, Object?)>(_entry, (
    fromWorker.sendPort,
    main,
    init,
  ), debugName: debugName);
  return _IsolateChannel(isolate, await ready.future, fromWorker);
}

void _entry((SendPort, WorkerMain, Object?) start) {
  final (reply, main, init) = start;
  final port = ReceivePort();
  reply.send(port.sendPort);
  main(init, reply.send, (onMessage) => port.listen(onMessage), port.close);
}

class _IsolateChannel implements WorkerChannel {
  _IsolateChannel(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  @override
  void send(Object? message) => _toWorker.send(message);

  @override
  void close() {
    _fromWorker.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}
