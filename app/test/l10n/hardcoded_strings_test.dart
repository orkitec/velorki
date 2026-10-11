import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps English out of the translated app.
///
/// Every sentence the rider reads comes from `app_en.arb` through
/// `AppLocalizations`; a literal in a widget is English in every language. This
/// scans `lib/` for the places such a literal ends up on the screen — a `Text`,
/// a `TextSpan`, a tooltip, a label or hint, a title, a snack bar's or a
/// notification's text, a share subject — and for an exception's English
/// `message` or `toString()` handed to the screen instead of `errorText`.
/// A hit that is meant to stay goes into [_allowed] with the reason.
void main() {
  final List<File> sources =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !_generated(f.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('finds the sources', () {
    expect(sources.length, greaterThan(100));
  });

  test('the scanner sees what it is meant to see', () {
    expect(_scan('Text("Hello")'), hasLength(1));
    expect(_scan("const Text(\n  'Hello world',\n)"), hasLength(1));
    expect(_scan("tooltip: 'Back'"), hasLength(1));
    expect(_scan("TextSpan(text: 'Tap here')"), hasLength(1));
    expect(_scan("SnackBar(content: Text('Saved'))"), hasLength(1));
    expect(_scan("Text('\${a.b} km')"), hasLength(1));
    expect(_scan("Text('\$value')"), isEmpty);
    expect(_scan("Text('\${l10n.a} · \${l10n.b}')"), isEmpty);
    expect(_scan("Text('·')"), isEmpty);
    expect(_scan('Text(l10n.hello)'), isEmpty);
    expect(_scan("// Text('Hello')"), isEmpty);
    expect(_scan('label: Text(e.message)', presentation: true), hasLength(1));
    expect(
      _scan('l10n.failed(error.toString())', presentation: true),
      hasLength(1),
    );
    expect(_scan("Text('\$error')", presentation: true), hasLength(1));
  });

  test('every allowlist entry still matches a literal', () {
    final Set<String> seen = <String>{
      for (final File file in sources)
        for (final _Hit hit in _scan(
          file.readAsStringSync(),
          presentation: _isPresentation(file.path),
        ))
          '${_path(file)}|${hit.text}',
    };
    final List<String> stale = <String>[
      for (final _Allowed entry in _allowed)
        if (!seen.contains('${entry.path}|${entry.text}'))
          '${entry.path}: ${entry.text}',
    ];
    expect(stale, isEmpty, reason: 'remove these from the allowlist');
  });

  test('no user-visible English is hard-coded in lib/', () {
    final List<String> hits = <String>[
      for (final File file in sources)
        for (final _Hit hit in _scan(
          file.readAsStringSync(),
          presentation: _isPresentation(file.path),
        ))
          if (!_allowed.any((a) => a.path == _path(file) && a.text == hit.text))
            '${_path(file)}:${hit.line}: ${hit.text}',
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'move the text into lib/l10n/app_en.arb (and every other '
          'app_<lang>.arb) and read it through AppLocalizations; show '
          'exceptions with errorText(l10n, error). Only if it is not '
          'language (a brand, a symbol) add it to `_allowed` in this test.',
    );
  });
}

/// Literals that may stay as they are, and why.
const List<_Allowed> _allowed = <_Allowed>[
  _Allowed(
    'lib/features/recording/data/recording_service.dart',
    "'0.0 km · 00:00'",
    "numbers and a unit symbol: the notification's first line until the "
        'first update, which is worded in the rider\'s language and units',
  ),
  _Allowed(
    'lib/features/subscription/presentation/plus_upsell_card.dart',
    "'Plus'",
    'the product name, Velorki Plus, as a caption',
  ),
  _Allowed(
    'lib/features/weather/presentation/route_weather_section.dart',
    "'Plus'",
    'the product name, Velorki Plus, as a caption on the locked weather',
  ),
];

class _Allowed {
  const _Allowed(this.path, this.text, this.reason);

  /// The file, relative to the app package.
  final String path;

  /// The literal as written, quotes included.
  final String text;

  /// Why it is not translated.
  final String reason;
}

class _Hit {
  const _Hit(this.line, this.text);

  final int line;
  final String text;
}

/// Named arguments whose string ends up on the screen or in a notification.
const List<String> _visibleArguments = <String>[
  'tooltip',
  'label',
  'labelText',
  'hintText',
  'helperText',
  'errorText',
  'counterText',
  'prefixText',
  'suffixText',
  'title',
  'subtitle',
  'semanticLabel',
  'semanticsLabel',
  'semanticsValue',
  'message',
  'content',
  'text',
  'body',
  'subject',
  'notificationTitle',
  'notificationText',
  'channelName',
  'channelDescription',
  'barrierLabel',
];

final RegExp _widgetLiteral = RegExp(
  r'\b(?:Text|TextSpan|SelectableText|Tooltip|Tab|SectionCaption)\(\s*'
  r"""(?:text:\s*|message:\s*)?(?=r?['"])""",
);

final RegExp _argumentLiteral = RegExp(
  '\\b(?:${_visibleArguments.join('|')})\\s*:\\s*(?:const\\s+)?'
  r"""(?=r?['"])""",
);

/// An exception's own words handed to the screen.
final RegExp _rawError = RegExp(
  r'\b(?:e|error|err|failure)\.(?:message\b|toString\(\))'
  r"""|['"]\$\{?(?:e|error|err)\}?['"]""",
);

/// The hits in [source]; [presentation] adds the raw-error check.
List<_Hit> _scan(String source, {bool presentation = false}) {
  final String code = _withoutComments(source);
  final List<_Hit> out = <_Hit>[];
  final Set<int> seen = <int>{};
  int lineOf(int offset) =>
      '\n'.allMatches(code.substring(0, offset)).length + 1;
  for (final RegExp pattern in <RegExp>[_widgetLiteral, _argumentLiteral]) {
    for (final RegExpMatch m in pattern.allMatches(code)) {
      final int end = _literalEnd(code, m.end);
      if (end < 0 || !seen.add(m.end)) continue;
      final String literal = code.substring(m.end, end);
      if (_hasWords(literal)) out.add(_Hit(lineOf(m.end), literal));
    }
  }
  if (presentation) {
    for (final RegExpMatch m in _rawError.allMatches(code)) {
      out.add(_Hit(lineOf(m.start), m.group(0)!));
    }
  }
  out.sort((a, b) => a.line.compareTo(b.line));
  return out;
}

/// The index after the string literal that starts at [start], or -1 when it
/// is not a one-line literal. Interpolations may hold quotes of their own.
int _literalEnd(String code, int start) {
  var i = start;
  final bool raw = code[i] == 'r';
  if (raw) i++;
  final String quote = code[i];
  if (code.startsWith(quote * 3, i)) return -1;
  i++;
  while (i < code.length) {
    final String c = code[i];
    if (c == '\n') return -1;
    if (c == quote) return i + 1;
    if (!raw && c == '\\') {
      i += 2;
      continue;
    }
    if (!raw && c == r'$' && i + 1 < code.length && code[i + 1] == '{') {
      var depth = 1;
      i += 2;
      while (i < code.length && depth > 0) {
        final String d = code[i];
        if (d == '{') depth++;
        if (d == '}') depth--;
        if (d == "'" || d == '"') {
          final int inner = _literalEnd(code, i);
          if (inner < 0) return -1;
          i = inner;
          continue;
        }
        i++;
      }
      continue;
    }
    i++;
  }
  return -1;
}

/// Whether [literal] has a letter outside its interpolations.
bool _hasWords(String literal) {
  final bool raw = literal.startsWith('r');
  final String body = literal.substring(raw ? 2 : 1, literal.length - 1);
  final StringBuffer text = StringBuffer();
  var i = 0;
  while (i < body.length) {
    final String c = body[i];
    if (!raw && c == '\\') {
      i += 2;
    } else if (!raw && c == r'$' && body.startsWith('{', i + 1)) {
      // Skip the interpolation, nested braces and quotes included.
      var depth = 0;
      String? quote;
      for (i++; i < body.length; i++) {
        final String d = body[i];
        if (quote != null) {
          if (d == quote) quote = null;
        } else if (d == "'" || d == '"') {
          quote = d;
        } else if (d == '{') {
          depth++;
        } else if (d == '}' && --depth == 0) {
          break;
        }
      }
      i++;
    } else if (!raw && c == r'$') {
      i++;
      while (i < body.length && RegExp(r'\w').hasMatch(body[i])) {
        i++;
      }
    } else {
      text.write(c);
      i++;
    }
  }
  return RegExp(r'\p{L}', unicode: true).hasMatch(text.toString());
}

/// [source] with `//` comments blanked, keeping the line count, and with
/// `//` inside string literals (URLs) left alone.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) {
      final String trimmed = line.trimLeft();
      if (trimmed.startsWith('//')) return '';
      final int at = line.indexOf(RegExp(r'\s//\s'));
      return at < 0 ? line : line.substring(0, at);
    })
    .join('\n');

bool _generated(String path) =>
    path.contains('/generated/') ||
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.endsWith('.drift.dart');

bool _isPresentation(String path) =>
    path.contains('/presentation/') || path.startsWith('lib/app/');

String _path(File file) => file.path.replaceAll(r'\', '/');
