import 'dart:async';

import 'worker_channel_types.dart';

export 'worker_channel_types.dart';

/// Runs [main] on the calling event loop, for a platform without isolates.
///
/// Messages are delivered as their own events in both directions, as ports
/// deliver them, so the worker's side cannot tell the difference; the engine
/// yields to the event loop every `yieldInterval` expansions, which is when
/// the page gets to draw a frame.
Future<WorkerChannel> spawnWorkerChannel(
  WorkerMain main,
  Object? init,
  void Function(Object? message) onMessage, {
  String? debugName,
}) async {
  final channel = _InlineChannel();
  main(
    init,
    (message) => Timer.run(() {
      if (!channel._closed) onMessage(message);
    }),
    (handler) => channel._toWorker = handler,
    () => channel._toWorker = null,
  );
  return channel;
}

class _InlineChannel implements WorkerChannel {
  void Function(Object? message)? _toWorker;
  bool _closed = false;

  @override
  void send(Object? message) => Timer.run(() => _toWorker?.call(message));

  @override
  void close() => _closed = true;
}
