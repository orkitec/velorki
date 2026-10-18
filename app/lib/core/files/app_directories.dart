// Where the app keeps its files: path_provider's directories on the phone,
// fixed roots of the in-memory file system (package:velorki_io) in the
// browser, which has no path_provider.
export 'app_directories_native.dart'
    if (dart.library.js_interop) 'app_directories_web.dart';
