// How a `.gaz` is opened: the system's SQLite on the phone, SQLite compiled
// to WebAssembly over the in-memory files in the browser.
export 'gazetteer_sqlite_native.dart'
    if (dart.library.js_interop) 'gazetteer_sqlite_web.dart';
