/// Reads the common forms of OpenStreetMap's `opening_hours` tag.
///
/// The tag has a grammar of its own (months, week numbers, sunrise, school
/// holidays, comments, …). Only the forms most places use are read here:
/// `24/7`, weekdays (`Mo-Fr`, `Mo,We`, `Fr-Mo`), time ranges (`08:00-18:00`,
/// past midnight `18:00-02:00`), several of them (`08:00-12:00,14:00-18:00`),
/// `off` and `closed`, and rules joined by `;` or an additional `,`. Public
/// holidays (`PH`) are left out: the phone does not know them. Anything else
/// makes [OpeningHours.parse] answer `null`, so a value it cannot read gets
/// no status at all rather than a wrong one.
library;

/// Minutes in a day.
const int _day = 24 * 60;

/// Minutes in a week.
const int _week = 7 * _day;

/// The weekday abbreviations of the tag, Monday first.
const List<String> _weekdays = <String>[
  'Mo',
  'Tu',
  'We',
  'Th',
  'Fr',
  'Sa',
  'Su',
];

/// Whether a place is open at a moment, and when that changes.
class OpeningStatus {
  /// Creates a status.
  const OpeningStatus({required this.open, this.change});

  /// Whether the place is open.
  final bool open;

  /// When it closes (when [open]) or opens (when not), in local time;
  /// `null` when that does not happen within a week (open around the clock,
  /// or never open).
  final DateTime? change;

  @override
  bool operator ==(Object other) =>
      other is OpeningStatus && other.open == open && other.change == change;

  @override
  int get hashCode => Object.hash(open, change);

  @override
  String toString() => 'OpeningStatus(open: $open, change: $change)';
}

/// A week of opening hours read from an `opening_hours` value.
class OpeningHours {
  OpeningHours._(this._days);

  /// Per weekday (0 is Monday), the open intervals in minutes from that
  /// day's midnight; an end past [_day] runs into the next day.
  final List<List<(int, int)>> _days;

  /// The week [raw] describes, or `null` when it uses a form this reader
  /// does not know.
  static OpeningHours? parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final days = List<List<(int, int)>>.generate(7, (_) => <(int, int)>[]);
    var applied = false;
    for (final part in value.split(';')) {
      final rule = part.trim();
      if (rule.isEmpty) continue;
      // `Mo-Fr 08:00-12:00, Sa 09:00-12:00`: a second rule after a comma
      // adds to the first rather than replacing what it said.
      final pieces = rule.split(
        RegExp(r'(?<=\d|off|closed)\s*,\s*(?=(?:Mo|Tu|We|Th|Fr|Sa|Su|PH)\b)'),
      );
      for (final (i, piece) in pieces.indexed) {
        final read = _readPiece(piece.trim());
        if (read == null) return null;
        if (read.ignored) continue;
        applied = true;
        for (final d in read.days) {
          if (i == 0 || read.intervals.isEmpty) days[d].clear();
          days[d].addAll(read.intervals);
        }
      }
    }
    return applied ? OpeningHours._(days) : null;
  }

  /// Whether the place is open at [now] (local time), and when that changes.
  OpeningStatus status(DateTime now) {
    final spans = <(int, int)>[
      for (var w = -1; w <= 1; w++)
        for (var d = 0; d < 7; d++)
          for (final (start, end) in _days[d])
            (w * _week + d * _day + start, w * _week + d * _day + end),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final span in spans) {
      if (merged.isNotEmpty && span.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, span.$2 > last.$2 ? span.$2 : last.$2));
      } else {
        merged.add(span);
      }
    }
    final at = (now.weekday - 1) * _day + now.hour * 60 + now.minute;
    for (final (start, end) in merged) {
      if (start <= at && at < end) {
        return OpeningStatus(
          open: true,
          change: end - at >= _week ? null : _moment(now, end),
        );
      }
      if (start > at) {
        return OpeningStatus(open: false, change: _moment(now, start));
      }
    }
    return const OpeningStatus(open: false);
  }

  /// The local time [minute] minutes after the midnight that began the
  /// Monday of [now]'s week; by calendar, so a clock change is no matter.
  static DateTime _moment(DateTime now, int minute) => DateTime(
    now.year,
    now.month,
    now.day - (now.weekday - 1) + minute ~/ _day,
    (minute % _day) ~/ 60,
    minute % 60,
  );

  static _Piece? _readPiece(String piece) {
    if (piece == '24/7') {
      return _Piece(
        days: List<int>.generate(7, (d) => d),
        intervals: const <(int, int)>[(0, _day)],
      );
    }
    var rest = piece;
    List<int>? days;
    final selector = RegExp(
      r'^((?:Mo|Tu|We|Th|Fr|Sa|Su|PH)(?:\s*-\s*(?:Mo|Tu|We|Th|Fr|Sa|Su))?'
      r'(?:\s*,\s*(?:Mo|Tu|We|Th|Fr|Sa|Su|PH)'
      r'(?:\s*-\s*(?:Mo|Tu|We|Th|Fr|Sa|Su))?)*)(?=\s|$)',
    ).firstMatch(rest);
    if (selector != null) {
      final selected = <int>{};
      var holidaysOnly = true;
      for (final item in selector[1]!.split(',')) {
        final range = item.split('-').map((s) => s.trim()).toList();
        if (range.first == 'PH') continue;
        holidaysOnly = false;
        final from = _weekdays.indexOf(range.first);
        final to = range.length > 1 ? _weekdays.indexOf(range[1]) : from;
        for (var d = from; ; d = (d + 1) % 7) {
          selected.add(d);
          if (d == to) break;
        }
      }
      rest = rest.substring(selector.end).trim();
      if (rest.isEmpty) return null;
      if (holidaysOnly) return const _Piece.ignored();
      days = selected.toList()..sort();
    }
    days ??= List<int>.generate(7, (d) => d);
    if (rest == 'off' || rest == 'closed') {
      return _Piece(days: days, intervals: const <(int, int)>[]);
    }
    final intervals = <(int, int)>[];
    for (final range in rest.split(',')) {
      final m = RegExp(r'^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$')
          .firstMatch(range.trim());
      if (m == null) return null;
      final startH = int.parse(m[1]!);
      final startM = int.parse(m[2]!);
      final endH = int.parse(m[3]!);
      final endM = int.parse(m[4]!);
      if (startM > 59 || endM > 59 || startH > 24 || endH > 48) return null;
      final start = startH * 60 + startM;
      var end = endH * 60 + endM;
      if (start >= _day) return null;
      if (end == start) return null;
      // `18:00-02:00` runs past midnight.
      if (end <= start) end += _day;
      if (end <= start || end > 2 * _day) return null;
      intervals.add((start, end));
    }
    return _Piece(days: days, intervals: intervals);
  }
}

/// What one rule says: the days it is about and when they are open (none:
/// closed), or that it is about public holidays only.
class _Piece {
  const _Piece({required this.days, required this.intervals}) : ignored = false;

  const _Piece.ignored()
    : days = const <int>[],
      intervals = const <(int, int)>[],
      ignored = true;

  final List<int> days;
  final List<(int, int)> intervals;
  final bool ignored;
}

/// [raw] as lines to show, one rule each, with a space after each comma.
List<String> openingHoursLines(String raw) => <String>[
  for (final rule in raw.split(';'))
    if (rule.trim().isNotEmpty)
      rule.trim().replaceAll(RegExp(r'\s*,\s*'), ', '),
];
