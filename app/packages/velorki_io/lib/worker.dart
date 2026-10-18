/// Work off the caller's event loop: an isolate of its own where there are
/// isolates, the calling event loop in a browser, where `Isolate.spawn` and
/// `Isolate.run` throw.
///
/// [spawnWorkerChannel] starts a long-lived worker that is talked to through
/// messages; [runIsolated] runs one computation and returns its result.
library;

export 'src/worker_channel.dart';
