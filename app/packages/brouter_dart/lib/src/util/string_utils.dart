// Port of btools.util.StringUtils (BRouter v1.7.10).

/// Some methods for String handling
class StringUtils {
  StringUtils._();

  static const List<String> _xmlChr = [
    '&',
    '<',
    '>',
    "'",
    '"',
    '\t',
    '\n',
    '\r',
  ];
  static const List<String> _xmlEsc = [
    '&amp;', '&lt;', '&gt;', '&apos;', '&quot;', '&#x9;', '&#xA;', '&#xD;', //
  ];

  static const List<String> _jsnChr = ["'", '"', '\\', '/'];
  static const List<String> _jsnEsc = ["\\'", '\\"', '\\\\', '\\/'];

  /// Escape a literal to put into a json document
  static String escapeJson(String s) {
    return _escape(s, _jsnChr, _jsnEsc);
  }

  /// Escape a literal to put into a xml document
  static String escapeXml10(String s) {
    return _escape(s, _xmlChr, _xmlEsc);
  }

  static String _escape(String s, List<String> chr, List<String> esc) {
    StringBuffer? sb;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      var j = 0;
      while (j < chr.length) {
        if (c == chr[j]) {
          sb ??= StringBuffer(s.substring(0, i));
          sb.write(esc[j]);
          break;
        }
        j++;
      }
      if (sb != null && j == chr.length) {
        sb.write(c);
      }
    }
    return sb == null ? s : sb.toString();
  }
}
