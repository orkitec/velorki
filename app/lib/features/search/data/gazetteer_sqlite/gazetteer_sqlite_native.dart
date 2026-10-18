import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart';

/// Nothing to load on the phone: SQLite is linked in.
Future<void> prepareGazetteerSqlite() async {}

/// Opens the gazetteer at [path] read-only.
CommonDatabase openGazetteerFile(String path) =>
    sqlite3.open(path, mode: OpenMode.readOnly);
