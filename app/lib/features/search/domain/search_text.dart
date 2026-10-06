/// How a typed query and a stored name are read for matching: the words, the
/// house number, and how well one word stands for another.
///
/// Pure Dart and free of any language: no word lists, no abbreviation tables.
/// What a word may stand for is decided by its letters alone — equal, a
/// prefix, an abbreviation made of its letters in order, one or two edits
/// away, two words written as one — and the rest is left to the index, which
/// knows which words exist.
library;

import 'dart:math' as math;

import 'fuzzy.dart';
import 'translit.dart';

/// [text] folded for comparing two words: [foldSearchTerm], Cyrillic and
/// Greek spelled in Latin ([transliterate]), and the letters that are
/// written two ways ("ß" and "ss", "æ" and "ae").
///
/// The index keeps "ß" as it is, so this is only ever used on the Dart side,
/// on both the query and the name, never to build an FTS term.
String foldForMatch(String text) {
  final folded = transliterate(foldSearchTerm(text));
  if (!_twoWayLetters.hasMatch(folded)) return folded;
  return folded.replaceAllMapped(_twoWayLetters, (m) => _twoWay[m[0]] ?? m[0]!);
}

/// [text] folded like [foldForMatch] but with Cyrillic spelled the Ukrainian
/// way ([transliterateUk]): the second spelling a name with a Ukrainian
/// letter is indexed in.
String foldForMatchUk(String text) {
  final folded = transliterateUk(foldSearchTerm(text));
  if (!_twoWayLetters.hasMatch(folded)) return folded;
  return folded.replaceAllMapped(_twoWayLetters, (m) => _twoWay[m[0]] ?? m[0]!);
}

const Map<String, String> _twoWay = <String, String>{
  'ß': 'ss',
  'ẞ': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'ø': 'o',
  'đ': 'd',
  'ð': 'd',
  'þ': 'th',
  'ı': 'i',
};
final RegExp _twoWayLetters = RegExp('[ßẞæœøđðþı]');

/// The words of [text] the way the index's tokenizer cuts them: runs of
/// letters, marks and digits, everything else a separator.
///
/// "C/ Mayor" is `[C, Mayor]`, "Saint-Denis" `[Saint, Denis]`, "12/3" `[12, 3]`.
/// The words keep their case and accents; [foldForMatch] them to compare.
List<String> indexWords(String text) => <String>[
  for (final m in _wordRun.allMatches(text)) m[0]!,
];

final RegExp _wordRun = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

/// A typed query, read.
class ParsedQuery {
  /// Creates a parsed query.
  const ParsedQuery({required this.words, this.houseNumber, this.number});

  /// The words to look for, as typed, in order.
  final List<String> words;

  /// The house number as typed ("12a", "12 bis", "12/3"), or `null`.
  final String? houseNumber;

  /// The number [houseNumber] starts with, which is what an address is
  /// located by.
  final int? number;
}

/// The most words one query is read as; the rest is a paste accident.
const int maxQueryWords = 8;

/// [text] split into the words to look for and the house number, if any.
///
/// A house number is the first token that is a number, with or without a
/// letter of any script or a "bis" after it ("12", "12a", "12а", "12bis",
/// "12 bis", "12/3", "12/A", "12-14", "92-10"), anywhere in the query, as
/// long as there is a word to go with it: a query that is only a number is
/// that number. An ordinal ("42nd", "1.", "2º", "5e") is a name. A postcode
/// — five or more digits, or four digits and two letters — in a query that
/// has words is dropped: no name in the index carries one.
ParsedQuery parseQuery(String text) {
  final tokens = <String>[
    for (final t in text.trim().split(_tokenSeparator))
      if (t.isNotEmpty) t,
  ];
  // "400w 42nd": a number glued to a compass letter is two tokens.
  if (tokens.isNotEmpty) {
    final glued = _numberCompass.firstMatch(tokens.first);
    if (glued != null) {
      tokens
        ..removeAt(0)
        ..insertAll(0, <String>[glued[1]!, glued[2]!]);
    }
  }

  final hasWord = tokens.any(_isWord);
  // "1012 AB": four digits and two letters are a Dutch postcode, not a
  // house number and a word.
  final postcodes = <int>{};
  for (var i = 0; i + 1 < tokens.length; i++) {
    if (_fourDigits.hasMatch(tokens[i]) &&
        _twoLetters.hasMatch(tokens[i + 1])) {
      postcodes.addAll(<int>[i, i + 1]);
    }
  }
  String? houseNumber;
  int? number;
  final words = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (hasWord && postcodes.contains(i)) continue;
    if (hasWord && houseNumber == null && !_isOrdinal(token)) {
      final m = _houseNumber.firstMatch(token);
      if (m != null) {
        houseNumber = token;
        number = int.tryParse(m[1]!);
        // "12 bis", "12 a": the suffix is part of the number.
        if (m[2] == null &&
            m[3] == null &&
            i + 1 < tokens.length &&
            _numberSuffix.hasMatch(tokens[i + 1])) {
          houseNumber = '$token ${tokens[i + 1]}';
          i++;
        }
        continue;
      }
    }
    if (hasWord && _postcode.hasMatch(token)) continue;
    words.addAll(indexWords(token));
  }
  return ParsedQuery(
    words: words.length > maxQueryWords
        ? words.sublist(0, maxQueryWords)
        : words,
    houseNumber: houseNumber,
    number: number,
  );
}

final RegExp _tokenSeparator = RegExp(r'[\s,;]+');
final RegExp _numberCompass = RegExp(r'^(\d+)([nsewNSEW])$');
final RegExp _letter = RegExp(r'\p{L}', unicode: true);

/// "12", "12a", "12а" (any script), "12bis", "12/3", "12/A", "40-42",
/// "12a-14", "92-10".
final RegExp _houseNumber = RegExp(
  r'^(\d{1,4})(\p{L}|bis|ter|quater)?(?:[/\-](\d{1,4}\p{L}?|\p{L}))?$',
  unicode: true,
);
final RegExp _numberSuffix = RegExp(r'^(?:[a-dA-Dа-гА-Г]|bis|ter|quater)$');
final RegExp _postcode = RegExp(r'^\d{5,}$');
final RegExp _fourDigits = RegExp(r'^\d{4}$');
final RegExp _twoLetters = RegExp(r'^[A-Za-z]{2}$');
final RegExp _ordinal = RegExp(
  r'^\d+(?:st|nd|rd|th|e|er|re|eme|ème|º|ª|°|\.|a\.|o\.)$',
  caseSensitive: false,
);

bool _isOrdinal(String token) => _ordinal.hasMatch(token);

/// Whether [token] is a word a house number can belong to.
bool _isWord(String token) =>
    _isOrdinal(token) ||
    (_letter.hasMatch(token) &&
        _houseNumber.firstMatch(token) == null &&
        !_numberSuffix.hasMatch(token));

/// The letter-count up to which a word may be one edit away, not two.
const int _oneEditMaxChars = 5;

/// Words this short are never guessed at: too many words are one edit away.
const int _minTypoChars = 4;

/// How many edits [word] may be away from the word it meant.
int allowedEdits(String word) => word.length < _minTypoChars
    ? 0
    : word.length <= _oneEditMaxChars
    ? 1
    : 2;

/// How well the typed word [query] stands for the stored word [name], both
/// [foldForMatch]ed: 1 for the same word, 0 for none, and in between for a
/// prefix, an abbreviation, a typo.
double wordMatch(String query, String name) {
  if (query == name) return 1;
  if (query.isEmpty || name.isEmpty) return 0;
  if (name.startsWith(query)) {
    // "str" for "strasse", "w" for "west", or a word still being typed.
    return 0.8 + 0.18 * query.length / name.length;
  }
  var best = 0.0;
  if (query.length >= 2 &&
      query.length < name.length &&
      query.codeUnitAt(0) == name.codeUnitAt(0) &&
      _isSubsequence(query, name)) {
    // "rd" for "road", "blvd" for "boulevard": the letters, in order.
    best = query.length <= 4 ? 0.72 : 0.6;
  } else if (name.length >= 2 &&
      name.length <= 4 &&
      name.length < query.length &&
      query.codeUnitAt(0) == name.codeUnitAt(0) &&
      _isSubsequence(name, query)) {
    // The name is the short one: "st" stored, "saint" typed.
    best = 0.72;
  }
  final edits = allowedEdits(query);
  if (edits > 0) {
    final distance = damerauLevenshtein(query, name, max: edits);
    if (distance <= edits) best = math.max(best, 0.8 - 0.12 * distance);
    // A mistyped word that is still being typed: "brookyl" for "brooklyn".
    if (name.length > query.length) {
      final head = name.substring(0, query.length);
      if (damerauLevenshtein(query, head, max: 1) <= 1) {
        best = math.max(best, 0.62);
      }
    }
  }
  return best;
}

bool _isSubsequence(String short, String long) {
  var j = 0;
  for (var i = 0; i < long.length && j < short.length; i++) {
    if (long.codeUnitAt(i) == short.codeUnitAt(j)) j++;
  }
  return j == short.length;
}

/// How well a stored name answers a query.
class NameMatch {
  /// Creates a match.
  const NameMatch({
    required this.quality,
    required this.unmatched,
    required this.corrected,
    this.complete = false,
    this.usedContext = false,
  });

  /// 0 to a little over 1: how much of the query the name answers, how much
  /// of the name the query asked for, and a bonus for the very same name.
  final double quality;

  /// Indexes of the query words this name did not answer at all.
  final List<int> unmatched;

  /// Query word index → the name word it was read as, for every word that
  /// matched only as a typo or an abbreviation.
  final Map<int, String> corrected;

  /// Whether the name holds every query word exactly as it was typed.
  final bool complete;

  /// Whether the place the row lies in answered a query word.
  final bool usedContext;

  /// The same match, its [quality] times [share].
  NameMatch scaled(double share) => NameMatch(
    quality: quality * share,
    unmatched: unmatched,
    corrected: corrected,
    complete: complete,
    usedContext: usedContext,
  );

  /// Nothing matched.
  static const NameMatch none = NameMatch(
    quality: 0,
    unmatched: <int>[],
    corrected: <int, String>{},
  );
}

/// What a query word matched in a name worth less than this is not a match.
const double _matchFloor = 0.55;

/// A word matched below this was guessed at: a typo or an abbreviation.
const double _guessedBelow = 0.78;

/// How much an exact name is worth above a name that only holds the words.
const double exactNameBonus = 0.08;

/// What a query word is worth when the place a row lies in answers it.
const double contextMatch = 0.9;

/// How well [name] answers [query] (both lists of [foldForMatch]ed words).
///
/// Every query word is matched against the name's words on its own, and
/// against two neighbouring name words written as one ("hauptstrasse" for
/// "Haupt Strasse"); two neighbouring query words written apart are matched
/// against one name word ("haupt strasse" for "Hauptstrasse"). A query word
/// weighs by its length, so a stray letter costs less than a whole word. The
/// quality is the weighted share of the query that was answered, scaled by
/// the share of the name's letters that were asked for — "Monte" answers
/// "monte" better than "Monte Tea House" does — plus [exactNameBonus] when
/// the two are the same words.
///
/// [context] are the words of the place the row lies in: a query word the
/// name does not hold but the place does ("hauptstrasse berlin") is answered
/// at [contextMatch] and does not count against the name.
NameMatch matchName(
  List<String> query,
  List<String> name, {
  Set<String> context = const <String>{},
}) {
  if (query.isEmpty || name.isEmpty) return NameMatch.none;
  final scores = List<double>.filled(query.length, 0);
  final used = List<bool>.filled(name.length, false);
  final corrected = <int, String>{};
  var usedContext = false;

  // Two typed words that are one stored word.
  for (var i = 0; i + 1 < query.length; i++) {
    final joined = query[i] + query[i + 1];
    for (var j = 0; j < name.length; j++) {
      final s = wordMatch(joined, name[j]);
      if (s < _guessedBelow) continue;
      final value = math.min(s, 0.95);
      if (value > scores[i] && value > scores[i + 1]) {
        scores[i] = value;
        scores[i + 1] = value;
        used[j] = true;
      }
    }
  }

  for (var i = 0; i < query.length; i++) {
    final q = query[i];
    var best = scores[i];
    int? bestWord;
    var bestSpan = 1;
    for (var j = 0; j < name.length; j++) {
      // A word the name has already given to an earlier query word is worth
      // less, so "bergen bergen" does not answer "bergen" twice over.
      final s = wordMatch(q, name[j]) * (used[j] ? 0.5 : 1);
      if (s > best) {
        best = s;
        bestWord = j;
        bestSpan = 1;
      }
      if (j + 1 < name.length && !used[j] && !used[j + 1]) {
        final value = math.min(wordMatch(q, name[j] + name[j + 1]), 0.95);
        if (value > best) {
          best = value;
          bestWord = j;
          bestSpan = 2;
        }
      }
    }
    if (best < _matchFloor) {
      scores[i] = context.contains(q) ? contextMatch : 0;
      if (scores[i] > 0) usedContext = true;
      continue;
    }
    scores[i] = best;
    if (bestWord != null) {
      for (var k = 0; k < bestSpan; k++) {
        used[bestWord + k] = true;
      }
      if (best < _guessedBelow) {
        corrected[i] = bestSpan == 1
            ? name[bestWord]
            : name[bestWord] + name[bestWord + 1];
      }
    }
  }

  var weight = 0.0;
  var answered = 0.0;
  var exactWords = 0;
  final unmatched = <int>[];
  for (var i = 0; i < query.length; i++) {
    final w = math.max(2, query[i].length).toDouble();
    weight += w;
    answered += w * scores[i];
    if (scores[i] == 0) unmatched.add(i);
    if (scores[i] >= 0.999) exactWords++;
  }
  var nameLetters = 0;
  var askedLetters = 0;
  for (var j = 0; j < name.length; j++) {
    nameLetters += name[j].length;
    if (used[j]) askedLetters += name[j].length;
  }
  final coverage = answered / weight;
  final asked = nameLetters == 0 ? 0.0 : askedLetters / nameLetters;
  var quality = coverage * (0.7 + 0.3 * asked);
  if (query.length == name.length && scores.every((s) => s >= 0.999)) {
    quality += exactNameBonus;
  }
  return NameMatch(
    quality: quality,
    unmatched: unmatched,
    corrected: corrected,
    complete: exactWords == query.length,
    usedContext: usedContext,
  );
}
