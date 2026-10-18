import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:velorki/features/search/data/gazetteer_sqlite/files_vfs.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';

/// The file system the browser's SQLite reads gazetteers through. It is
/// plain `package:sqlite3/common.dart`, so the VM's SQLite can run it too:
/// the same file, the same queries, only the engine underneath differs.
void main() {
  const fixture = '../tools/gazetteer/fixtures/W20_N30.gaz';
  late FilesVfs vfs;

  setUpAll(() {
    vfs = FilesVfs(name: 'velorki-files-test');
    sqlite3.registerVirtualFileSystem(vfs);
  });
  tearDownAll(() => sqlite3.unregisterVirtualFileSystem(vfs));

  test('opens a gazetteer read-only in place and answers queries', () {
    final db = sqlite3.open(
      fixture,
      vfs: 'velorki-files-test',
      mode: OpenMode.readOnly,
    );
    addTearDown(db.close);
    final version = db.select('SELECT value FROM meta WHERE key = ?', <Object?>[
      'schema_version',
    ]);
    expect(version.single['value'].toString(), gazetteerSchemaVersion);
    // A sort over a whole table, which may need a temporary file of
    // SQLite's own: it goes to the scratch map, never to the files.
    final names = db.select(
      'SELECT name FROM places ORDER BY lower(name) DESC LIMIT 3',
    );
    expect(names, hasLength(3));
  });

  test('refuses to write and to open what is not there', () {
    final db = sqlite3.open(
      fixture,
      vfs: 'velorki-files-test',
      mode: OpenMode.readOnly,
    );
    addTearDown(db.close);
    expect(
      () => db.execute("INSERT INTO meta (key, value) VALUES ('x', 'y')"),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => sqlite3.open(
        '../tools/gazetteer/fixtures/missing.gaz',
        vfs: 'velorki-files-test',
        mode: OpenMode.readOnly,
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
