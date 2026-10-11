// Store listing texts: every translated store locale has every file en-US has
// (not blank), and every slides_<lang>.json has exactly slides_en.json's keys.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _storeLocale = RegExp(r'^[a-z]{2,3}(-[A-Za-z0-9]+)?$');

Set<String> _flat(Map<String, dynamic> map, [String prefix = '']) => {
  for (final e in map.entries)
    if (e.value is Map<String, dynamic>)
      ..._flat(e.value as Map<String, dynamic>, '$prefix${e.key}.')
    else
      '$prefix${e.key}',
};

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  for (final store in ['ios', 'android']) {
    final root = Directory('fastlane/metadata/$store');
    final source = Directory('${root.path}/en-US');
    final files = [
      for (final f in source.listSync().whereType<File>())
        f.uri.pathSegments.last,
    ]..sort();
    final locales = [
      for (final d in root.listSync().whereType<Directory>())
        if (_storeLocale.hasMatch(
              d.uri.pathSegments[d.uri.pathSegments.length - 2],
            ) &&
            d.uri.pathSegments[d.uri.pathSegments.length - 2] != 'en-US')
          d.uri.pathSegments[d.uri.pathSegments.length - 2],
    ]..sort();

    test('$store: there are texts to compare', () {
      expect(files, isNotEmpty);
      expect(locales, isNotEmpty);
    });

    for (final locale in locales) {
      test('$store/$locale has every en-US file, not blank', () {
        for (final name in files) {
          final f = File('${root.path}/$locale/$name');
          expect(f.existsSync(), isTrue, reason: '$locale/$name is missing');
          expect(
            f.readAsStringSync().trim(),
            isNotEmpty,
            reason: '$locale/$name is blank',
          );
        }
      });
    }
  }

  final en = _json('store/slides_en.json');
  final enKeys = _flat(en);
  final others = [
    for (final f in Directory('store').listSync().whereType<File>())
      if (RegExp(r'^slides_(?!en\.)\w+\.json$')
          .hasMatch(f.uri.pathSegments.last))
        f.path,
  ]..sort();

  test(
    'there are translated slides to compare',
    () => expect(others, isNotEmpty),
  );

  for (final path in others) {
    test('$path has the keys of slides_en.json and no others', () {
      final data = _json(path);
      expect(_flat(data), enKeys);
      void notBlank(Map<String, dynamic> m, String p) {
        for (final e in m.entries) {
          final v = e.value;
          if (v is Map<String, dynamic>) {
            notBlank(v, '$p${e.key}.');
          } else if (v is String) {
            expect(v.trim(), isNotEmpty, reason: '$p${e.key} is blank');
          }
        }
      }

      notBlank(data, '');
    });
  }
}
