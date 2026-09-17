import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/files/backup_exclusion.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';

import 'support/fake_segments.dart';

/// Records what [BrouterStorage.create] asked to be kept out of the backup.
class _FakeBackupExclusion implements BackupExclusion {
  final List<String> excluded = <String>[];

  @override
  Future<bool> exclude(Directory dir) async {
    excluded.add(dir.path);
    return true;
  }
}

void main() {
  test('create makes the three directories and excludes the root', () async {
    final backup = _FakeBackupExclusion();
    final root = Directory('${tempDir('velorki-storage').path}/brouter');

    final storage = await BrouterStorage(root, backup: backup).create();

    expect(storage.segments.existsSync(), isTrue);
    expect(storage.profiles.existsSync(), isTrue);
    expect(storage.gazetteer.existsSync(), isTrue);
    expect(backup.excluded, <String>[root.path]);
  });
}
