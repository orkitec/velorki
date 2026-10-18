// The web side of a conditional import: what uses it is the same import
// on the phone side, which is the side dart_code_linter follows.
// ignore_for_file: unused-code

import 'package:velorki_io/io.dart';

/// The in-memory file system's support root; what is kept across visits is
/// decided by the browser store (`web_file_store.dart`).
Future<Directory> appSupportDirectory() async =>
    Directory('/support')..createSync(recursive: true);

/// The in-memory file system's cache root.
Future<Directory> appCacheDirectory() async =>
    Directory('/cache')..createSync(recursive: true);

/// The in-memory file system's temporary root, never kept.
Future<Directory> appTemporaryDirectory() async =>
    Directory('/tmp')..createSync(recursive: true);
