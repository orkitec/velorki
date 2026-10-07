/// The Latin a rider types for the letters of Cyrillic and Greek names.
///
/// A copy of `tools/gazetteer/translit.json`, which the builder indexes names
/// with (`meta.search_script` = `latin`); `translit_test.dart` keeps the two
/// equal. One table per script and no language lists: where languages
/// spell a letter differently, the commonest rider spelling wins.
library;

/// Two letters that start a word → their Latin spelling: Greek "μπ" is "b"
/// at the start of a word ("Μπάρι"), "mp" inside one.
const Map<String, String> transliterationStarts = <String, String>{
  'μπ': 'b',
  'ντ': 'd',
  'γκ': 'g',
};

/// Two letters that are not the sum of their parts: Greek "ου" is "ou",
/// "αυ" and "ευ" are "av" and "ev".
const Map<String, String> transliterationDigraphs = <String, String>{
  'ου': 'ou',
  'ού': 'ou',
  'αυ': 'av',
  'αύ': 'av',
  'ευ': 'ev',
  'εύ': 'ev',
  'ηυ': 'iv',
  'ηύ': 'iv',
};

/// The Ukrainian national romanisation, the spelling on Ukrainian signs and
/// in the official Latin names: word starts (є ye, ї yi, й y, ю yu, я ya).
const Map<String, String> transliterationStartsUk = <String, String>{
  'є': 'ye',
  'ї': 'yi',
  'й': 'y',
  'ю': 'yu',
  'я': 'ya',
};

/// The Ukrainian national romanisation, letter by letter (г h, х kh, и y).
const Map<String, String> transliterationUk = <String, String>{
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'h',
  'ґ': 'g',
  'д': 'd',
  'е': 'e',
  'є': 'ie',
  'ж': 'zh',
  'з': 'z',
  'и': 'y',
  'і': 'i',
  'ї': 'i',
  'й': 'i',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'kh',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'shch',
  'ю': 'iu',
  'я': 'ia',
  'ь': '',
  'ъ': '',
  'ы': 'y',
  'э': 'e',
  'ё': 'yo',
  'ў': 'u',
  'ђ': 'dj',
  'ј': 'j',
  'љ': 'lj',
  'њ': 'nj',
  'ћ': 'c',
  'џ': 'dz',
  'ѓ': 'gj',
  'ќ': 'kj',
  'ѕ': 'dz',
};

/// Lower-case letter → its Latin spelling.
const Map<String, String> transliteration = <String, String>{
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'e',
  'ж': 'zh',
  'з': 'z',
  'и': 'i',
  'й': 'y',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'h',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sht',
  'ъ': 'a',
  'ы': 'y',
  'ь': '',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya',
  'є': 'ye',
  'і': 'i',
  'ї': 'yi',
  'ґ': 'g',
  'ў': 'u',
  'ђ': 'dj',
  'ј': 'j',
  'љ': 'lj',
  'њ': 'nj',
  'ћ': 'c',
  'џ': 'dz',
  'ѓ': 'gj',
  'ќ': 'kj',
  'ѕ': 'dz',
  'α': 'a',
  'β': 'v',
  'γ': 'g',
  'δ': 'd',
  'ε': 'e',
  'ζ': 'z',
  'η': 'i',
  'θ': 'th',
  'ι': 'i',
  'κ': 'k',
  'λ': 'l',
  'μ': 'm',
  'ν': 'n',
  'ξ': 'x',
  'ο': 'o',
  'π': 'p',
  'ρ': 'r',
  'σ': 's',
  'ς': 's',
  'τ': 't',
  'υ': 'y',
  'φ': 'f',
  'χ': 'ch',
  'ψ': 'ps',
  'ω': 'o',
  'ά': 'a',
  'έ': 'e',
  'ή': 'i',
  'ί': 'i',
  'ό': 'o',
  'ύ': 'y',
  'ώ': 'o',
  'ϊ': 'i',
  'ϋ': 'y',
  'ΐ': 'i',
  'ΰ': 'y',
};

/// [lowerCased] with its word starts, digraphs and letters spelled in Latin
/// and everything else left as it is.
String transliterate(String lowerCased) {
  var text = lowerCased;
  if (_starts.hasMatch(text)) {
    text = text.replaceAllMapped(_starts, (m) => transliterationStarts[m[1]]!);
  }
  if (_digraphs.hasMatch(text)) {
    text = text.replaceAllMapped(
      _digraphs,
      (m) => transliterationDigraphs[m[0]]!,
    );
  }
  StringBuffer? out;
  for (var i = 0; i < text.length; i++) {
    final latin = transliteration[text[i]];
    if (latin == null) {
      out?.write(text[i]);
      continue;
    }
    out ??= StringBuffer(text.substring(0, i));
    out.write(latin);
  }
  return out?.toString() ?? text;
}

final RegExp _starts = RegExp(
  '(?<!\\p{L})(${transliterationStarts.keys.join('|')})',
  unicode: true,
);
final RegExp _digraphs = RegExp(transliterationDigraphs.keys.join('|'));

/// Whether [text] has a letter only Ukrainian uses (і, ї, є, ґ): such a
/// name is indexed in both spellings, and a Latin query is matched against
/// both ([transliterateUk]).
bool hasUkrainianLetter(String text) => _ukrainianLetter.hasMatch(text);

final RegExp _ukrainianLetter = RegExp('[іїєґІЇЄҐ]');

/// [lowerCased] spelled the Ukrainian way: word starts, then letter by
/// letter, then everything else as [transliterate] spells it.
String transliterateUk(String lowerCased) {
  var text = lowerCased;
  if (_startsUk.hasMatch(text)) {
    text = text.replaceAllMapped(
      _startsUk,
      (m) => transliterationStartsUk[m[1]]!,
    );
  }
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    out.write(transliterationUk[text[i]] ?? text[i]);
  }
  return transliterate(out.toString());
}

final RegExp _startsUk = RegExp(
  '(?<!\\p{L})(${transliterationStartsUk.keys.join('|')})',
  unicode: true,
);
