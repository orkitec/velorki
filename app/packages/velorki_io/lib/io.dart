/// `dart:io` where there is one; in the browser, an in-memory stand-in for
/// the files and directories Velorki reads and writes (see
/// [MemoryFileSystem]).
///
/// Import this instead of `dart:io` in code that has to run on the web too.
/// On the phone it *is* `dart:io`, so nothing changes there.
library;

export 'dart:io' if (dart.library.js_interop) 'src/memory_io.dart';
