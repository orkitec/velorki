/// The Latin a rider types for the letters of Cyrillic and Greek names.
///
/// A copy of `tools/gazetteer/translit.json`, which the builder indexes names
/// with (`meta.search_script` = `latin`); `translit_test.dart` keeps the two
/// equal. One table per script and no language lists: where languages
/// spell a letter differently, the commonest rider spelling wins.
library;

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

/// [lowerCased] with every letter of [transliteration] spelled in Latin and
/// everything else left as it is.
String transliterate(String lowerCased) {
  StringBuffer? out;
  for (var i = 0; i < lowerCased.length; i++) {
    final latin = transliteration[lowerCased[i]];
    if (latin == null) {
      out?.write(lowerCased[i]);
      continue;
    }
    out ??= StringBuffer(lowerCased.substring(0, i));
    out.write(latin);
  }
  return out?.toString() ?? lowerCased;
}
