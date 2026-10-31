import 'dart:io';

import 'package:path_provider/path_provider.dart' as pp;

/// `getApplicationDocumentsDirectory()`, where the database lives.
Future<Directory> appDocumentsDirectory() =>
    pp.getApplicationDocumentsDirectory();

/// `getApplicationSupportDirectory()`.
Future<Directory> appSupportDirectory() => pp.getApplicationSupportDirectory();

/// `getApplicationCacheDirectory()`.
Future<Directory> appCacheDirectory() => pp.getApplicationCacheDirectory();

/// `getTemporaryDirectory()`.
Future<Directory> appTemporaryDirectory() => pp.getTemporaryDirectory();
