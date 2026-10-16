// How the database is opened: a SQLite file on a background isolate on the
// phone, SQLite compiled to WebAssembly in a web worker in the browser.
export 'connection_native.dart'
    if (dart.library.js_interop) 'connection_web.dart';
