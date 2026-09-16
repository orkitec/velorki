/// Spelling help for the offline index: the folding its tokenizer does, and
/// the edit distance that decides what a mistyped word probably was.
///
/// Pure Dart, no Flutter, no SQLite: the gazetteer feeds it words and it
/// answers with numbers.
library;

import 'dart:math' as math;

/// [text] the way the index stores it: lower case, without diacritics.
///
/// The FTS5 index is built with `unicode61 remove_diacritics 2`, so its
/// vocabulary holds "munchen", never "München". A typed word has to be folded
/// the same way before it can be compared with a term out of that vocabulary.
String foldSearchTerm(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    buffer.writeCharCode(_folded[rune] ?? rune);
  }
  return buffer.toString();
}

/// The Damerau-Levenshtein distance between [a] and [b], counting an
/// insertion, a deletion, a substitution and a swap of two neighbours as one
/// edit each.
///
/// The restricted ("optimal string alignment") variant: a pair of letters is
/// swapped at most once, which is what a mistyped name is. Anything above
/// [max] is not worth computing, so the function gives up and answers
/// [max] + 1.
int damerauLevenshtein(String a, String b, {int max = 3}) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > max) return max + 1;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  final first = a.codeUnits;
  final second = b.codeUnits;
  var previous = List<int>.generate(second.length + 1, (i) => i);
  var beforePrevious = List<int>.filled(second.length + 1, 0);
  var current = List<int>.filled(second.length + 1, 0);

  for (var i = 1; i <= first.length; i++) {
    current[0] = i;
    var best = current[0];
    for (var j = 1; j <= second.length; j++) {
      final cost = first[i - 1] == second[j - 1] ? 0 : 1;
      var value = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
      if (i > 1 &&
          j > 1 &&
          first[i - 1] == second[j - 2] &&
          first[i - 2] == second[j - 1]) {
        value = math.min(value, beforePrevious[j - 2] + 1);
      }
      current[j] = value;
      if (value < best) best = value;
    }
    // Every later row is at least as large as the smallest cell of this one.
    if (best > max) return max + 1;
    final recycled = beforePrevious;
    beforePrevious = previous;
    previous = current;
    current = recycled;
  }
  return previous[second.length];
}

/// The letters `remove_diacritics 2` strips, and what is left of them.
final Map<int, int> _folded = _buildFolds();

Map<int, int> _buildFolds() {
  const List<(String, String)> groups = <(String, String)>[
    ('àáâãäåāăąǎȧ', 'a'),
    ('çćĉċč', 'c'),
    ('ďđ', 'd'),
    ('èéêëēĕėęěȩ', 'e'),
    ('ĝğġģ', 'g'),
    ('ĥħ', 'h'),
    ('ìíîïĩīĭįıǐ', 'i'),
    ('ĵ', 'j'),
    ('ķ', 'k'),
    ('ĺļľłŀ', 'l'),
    ('ñńņňŉ', 'n'),
    ('òóôõöøōŏőǒ', 'o'),
    ('ŕŗř', 'r'),
    ('śŝşš', 's'),
    ('ţťŧ', 't'),
    ('ùúûüũūŭůűųǔ', 'u'),
    ('ŵ', 'w'),
    ('ýÿŷ', 'y'),
    ('źżž', 'z'),
  ];
  final folds = <int, int>{};
  for (final (accented, plain) in groups) {
    final target = plain.codeUnitAt(0);
    for (final rune in accented.runes) {
      folds[rune] = target;
    }
  }
  return folds;
}
