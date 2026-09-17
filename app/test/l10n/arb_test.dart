import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the ARB files that Crowdin writes.
///
/// `app_en.arb` is the only file edited by hand; every other `app_<code>.arb`
/// arrives in a translation pull request. Two things must hold for such a file
/// to be safe to merge: it declares the locale its name promises, and it
/// carries no key the English source does not have (a stray key would be a
/// string nobody can see, or a leftover from a renamed one). There may be no
/// translated ARB at all yet, and that is fine.
void main() {
  final Directory dir = Directory('lib/l10n');
  final Map<String, Object?> source = jsonDecode(
    File('${dir.path}/app_en.arb').readAsStringSync(),
  ) as Map<String, Object?>;

  final List<File> translations =
      dir
          .listSync()
          .whereType<File>()
          .where(
            (f) => f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the English source is the template', () {
    expect(source['@@locale'], 'en');
  });

  for (final File file in translations) {
    final String name = file.uri.pathSegments.last;
    final String locale = name
        .substring('app_'.length, name.length - '.arb'.length)
        .replaceAll('-', '_');

    group(name, () {
      final Map<String, Object?> arb =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

      test('declares the locale in its file name', () {
        expect(arb['@@locale'], locale);
      });

      test('has no key the English source does not have', () {
        final Iterable<String> unknown = arb.keys.where((key) {
          if (key.startsWith('@@')) return false;
          final String message = key.startsWith('@') ? key.substring(1) : key;
          return !source.containsKey(message);
        });
        expect(unknown, isEmpty);
      });
    });
  }
}
