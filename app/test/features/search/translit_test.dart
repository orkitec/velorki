import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/domain/search_text.dart';
import 'package:velorki/features/search/domain/translit.dart';

void main() {
  test('the app spells letters exactly as the builder indexes them', () {
    final table =
        (jsonDecode(File('../tools/gazetteer/translit.json').readAsStringSync())
                as Map<String, Object?>)['letters']!
            as Map<String, Object?>;
    expect(transliteration, table);
  });

  test('Cyrillic and Greek read as a rider types them', () {
    expect(foldForMatch('Александър Невски'), 'aleksandar nevski');
    expect(foldForMatch('Θεσσαλονίκη'), 'thessaloniki');
    expect(foldForMatch('Ђурђевдан'), 'djurdjevdan');
    expect(foldForMatch('бул. Витоша'), 'bul. vitosha');
    expect(transliterate('vaduz'), 'vaduz', reason: 'Latin is left alone');
  });

  test('a Latin query matches a Cyrillic name', () {
    final match = matchName(
      indexWords('aleksandar nevski').map(foldForMatch).toList(),
      indexWords('Храм-паметник Св. Александър Невски')
          .map(foldForMatch)
          .toList(),
    );
    expect(match.unmatched, isEmpty);
  });
}
