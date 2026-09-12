import 'dart:io';
import 'dart:typed_data';

/// Where the GPX and FIT sample files live, relative to the package root that
/// `flutter test` runs from.
const String fixtureDirectory = 'test/features/import_export/fixtures';

/// The path of the fixture called [name].
String fixturePath(String name) => '$fixtureDirectory/$name';

/// The bytes of the fixture called [name].
Uint8List fixtureBytes(String name) =>
    File(fixturePath(name)).readAsBytesSync();
