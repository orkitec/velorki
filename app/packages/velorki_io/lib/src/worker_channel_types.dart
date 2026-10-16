/// The worker's entry point: answers what [listen] delivers through [send],
/// and [stop]s listening when told to.
typedef WorkerMain = void Function(
  Object? init,
  void Function(Object? message) send,
  void Function(void Function(Object? message) onMessage) listen,
  void Function() stop,
);

/// The caller's end of a worker.
abstract interface class WorkerChannel {
  /// Hands [message] to the worker.
  void send(Object? message);

  /// Stops the worker; nothing it sends afterwards arrives.
  void close();
}
