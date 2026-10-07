import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/domain/search_text.dart';
import 'package:velorki/features/search/domain/translit.dart';

void main() {
  test('the app spells letters exactly as the builder indexes them', () {
    final table = jsonDecode(
      File('../tools/gazetteer/translit.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(transliteration, table['letters']);
    expect(transliterationStarts, table['starts']);
    expect(transliterationDigraphs, table['digraphs']);
    expect(transliterationUk, table['letters_uk']);
    expect(transliterationStartsUk, table['starts_uk']);
  });

  test('Cyrillic and Greek read as a rider types them', () {
    expect(foldForMatch('Александър Невски'), 'aleksandar nevski');
    expect(foldForMatch('Θεσσαλονίκη'), 'thessaloniki');
    expect(foldForMatch('Ναύπλιο'), 'navplio');
    expect(foldForMatch('Λευκωσία'), 'levkosia');
    expect(foldForMatch('Λουτράκι'), 'loutraki');
    expect(foldForMatch('Μπάρι Ντόρα'), 'bari dora');
    expect(foldForMatch('Λάμπρος'), 'lampros', reason: 'μπ inside a word');
    expect(foldForMatch('Ђурђевдан'), 'djurdjevdan');
    expect(foldForMatch('бул. Витоша'), 'bul. vitosha');
    expect(transliterate('vaduz'), 'vaduz', reason: 'Latin is left alone');
  });

  test('a Ukrainian name reads both ways', () {
    expect(foldForMatch('Київ'), 'kiyiv');
    expect(foldForMatchUk('Київ'), 'kyiv');
    expect(foldForMatchUk('Кривий Ріг'), 'kryvyi rih');
    expect(foldForMatchUk('Єнакієве'), 'yenakiieve');
    expect(hasUkrainianLetter('Київ'), isTrue);
    expect(hasUkrainianLetter('Хмельницький'), isFalse);
    expect(hasUkrainianLetter('София'), isFalse);
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
