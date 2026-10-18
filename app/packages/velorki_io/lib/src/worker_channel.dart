// Where a worker runs: an isolate of its own where there are isolates, the
// calling event loop in a browser (Isolate.spawn throws there).

export 'worker_channel_isolate.dart'
    if (dart.library.js_interop) 'worker_channel_inline.dart';
