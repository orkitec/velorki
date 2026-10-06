import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/domain/search_text.dart';

List<String> _words(String text) => indexWords(text).map(foldForMatch).toList();

void main() {
  group('foldForMatch', () {
    test('folds case, accents and the letters written two ways', () {
      expect(foldForMatch('Hauptstraße'), 'hauptstrasse');
      expect(foldForMatch('Champs-Élysées'), 'champs-elysees');
      expect(foldForMatch('Æbeltoft'), 'aebeltoft');
      expect(foldForMatch('Œuvre'), 'oeuvre');
      expect(foldForMatch('București Constanța'), 'bucuresti constanta');
    });
  });

  group('indexWords', () {
    test('cuts where the index tokenizer cuts', () {
      expect(indexWords('C/ Mayor'), <String>['C', 'Mayor']);
      expect(indexWords("Rue de l'École"), <String>['Rue', 'de', 'l', 'École']);
      expect(indexWords('Saint-Denis'), <String>['Saint', 'Denis']);
      expect(indexWords('бул. Витоша'), <String>['бул', 'Витоша']);
    });
  });

  group('parseQuery', () {
    test('a house number is found wherever it stands', () {
      for (final (text, number) in <(String, String)>[
        ('Hauptstraße 12 Berlin', '12'),
        ('12 Hauptstraße', '12'),
        ('Hauptstraße 12', '12'),
        ('Rue du Lavoir 41b', '41b'),
        ('Rue du Lavoir 41 bis', '41 bis'),
        ('Via Roma 12/3', '12/3'),
        ('Middlewich Road 40-42', '40-42'),
        ('92-10 Roosevelt Avenue', '92-10'),
        ('Via Roma 12/A', '12/A'),
        ('ул. Витоша 12а', '12а'),
        ('Hauptstr. 12a-14', '12a-14'),
      ]) {
        final parsed = parseQuery(text);
        expect(parsed.houseNumber, number, reason: text);
        expect(parsed.number, int.parse(number.split(RegExp('[^0-9]')).first));
      }
      expect(parseQuery('Rue du Lavoir 41 bis').words, <String>[
        'Rue',
        'du',
        'Lavoir',
      ]);
    });

    test('an ordinal is a name and a lone number is what is searched', () {
      expect(parseQuery('W 42nd St').houseNumber, isNull);
      expect(parseQuery('W 42nd St').words, <String>['W', '42nd', 'St']);
      expect(parseQuery('2º').houseNumber, isNull);
      expect(parseQuery('400').houseNumber, isNull);
      expect(parseQuery('400').words, <String>['400']);
    });

    test('a Dutch postcode is dropped with its letters', () {
      final parsed = parseQuery('1012 AB Amsterdam Damrak 1');
      expect(parsed.houseNumber, '1');
      expect(parsed.words, <String>['Amsterdam', 'Damrak']);
    });

    test('a postcode is dropped, the first number wins', () {
      final parsed = parseQuery('781 Franklin Ave Brooklyn NY 11216 USA');
      expect(parsed.houseNumber, '781');
      expect(parsed.words, isNot(contains('11216')));
      expect(parseQuery('400 w 42nd 12').words, <String>['w', '42nd', '12']);
    });

    test('a number glued to a compass letter is two tokens', () {
      final parsed = parseQuery('400w 42nd');
      expect(parsed.houseNumber, '400');
      expect(parsed.words, <String>['w', '42nd']);
    });
  });

  group('wordMatch', () {
    test('the same word, a prefix, an abbreviation, a typo', () {
      expect(wordMatch('strasse', 'strasse'), 1);
      expect(wordMatch('str', 'strasse'), inInclusiveRange(0.8, 0.99));
      expect(wordMatch('rd', 'road'), closeTo(0.72, 1e-9));
      expect(wordMatch('blvd', 'boulevard'), closeTo(0.72, 1e-9));
      expect(
        wordMatch('saint', 'st'),
        closeTo(0.72, 1e-9),
        reason: 'the stored name may be the abbreviated one',
      );
      expect(wordMatch('brooklyyn', 'brooklyn'), closeTo(0.68, 1e-9));
      expect(wordMatch('funhaal', 'funchal'), closeTo(0.56, 1e-9));
      expect(wordMatch('vzduq', 'vaduz'), 0, reason: 'two edits, five letters');
      expect(wordMatch('abc', 'abd'), 0, reason: 'too short to guess at');
    });
  });

  group('matchName', () {
    test('the very same name beats a name that holds more', () {
      final exact = matchName(_words('monte'), _words('Monte'));
      final longer = matchName(_words('monte'), _words('Monte Tea House'));
      expect(exact.quality, greaterThan(longer.quality));
      expect(exact.complete, isTrue);
      expect(exact.quality, greaterThan(1));
    });

    test('compounds: one typed word for two stored ones, and back', () {
      expect(
        matchName(_words('hauptstrasse'), _words('Haupt Straße')).quality,
        greaterThan(0.9),
      );
      expect(
        matchName(_words('haupt strasse'), _words('Hauptstraße')).quality,
        greaterThan(0.9),
      );
      expect(
        matchName(_words('saint pauls'), _words("St Paul's")).quality,
        greaterThan(0.8),
      );
    });

    test('a word the place answers counts, and is reported', () {
      final without = matchName(
        _words('hauptstrasse berlin'),
        _words('Hauptstraße'),
      );
      final within = matchName(
        _words('hauptstrasse berlin'),
        _words('Hauptstraße'),
        context: <String>{'kreuzberg', 'berlin'},
      );
      expect(without.unmatched, <int>[1]);
      expect(without.usedContext, isFalse);
      expect(within.unmatched, isEmpty);
      expect(within.usedContext, isTrue);
      expect(within.quality, greaterThan(without.quality));
    });

    test('a guessed word is reported as what it was read as', () {
      final match = matchName(_words('funchall'), _words('Funchal'));
      expect(match.corrected, <int, String>{0: 'funchal'});
      expect(match.complete, isFalse);
    });

    test('a stored word counts once', () {
      expect(
        matchName(_words('bergen'), _words('Bergen')).quality,
        greaterThan(
          matchName(_words('bergen'), _words('Bergen Bergen')).quality,
        ),
      );
    });
  });
}
