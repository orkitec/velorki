import 'dart:typed_data';

import 'package:velorki/features/import_export/data/incoming_file_service.dart';

/// Incoming sources that never deliver anything, for tests that feed the
/// service directly.
class SilentSources implements IncomingSources {
  @override
  Future<List<Never>> initialSharedMedia() async => const [];

  @override
  Stream<List<Never>> sharedMediaStream() => const Stream.empty();

  @override
  Future<Uri?> initialLink() async => null;

  @override
  Stream<Uri> linkStream() => const Stream.empty();

  @override
  Stream<String> openedFilePaths() => const Stream.empty();

  @override
  Future<Uint8List?> readFile(String path) async => null;

  @override
  Future<Uint8List?> readContentUri(Uri uri) async => null;
}
