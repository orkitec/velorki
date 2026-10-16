// Where the RoutingWorker's engine runs: an isolate of its own where there
// are isolates, the calling event loop in a browser (Isolate.spawn throws
// there). Velorki's own code, not a port of an upstream class.

export 'worker_channel_isolate.dart'
    if (dart.library.js_interop) 'worker_channel_inline.dart';
