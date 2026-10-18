// How the map loads a file or a picture the app made: by its file:// URL
// or a data: URL on the phone; in the browser, whose files are in memory
// (package:velorki_io) and which maplibre cannot fetch, by a blob: URL of
// the bytes.
export 'local_file_url_native.dart'
    if (dart.library.js_interop) 'local_file_url_web.dart';
