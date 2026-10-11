import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/domain/opening_hours.dart';

/// Monday 5 October 2026, at [hour]:[minute], plus [days].
DateTime _mon(int hour, [int minute = 0, int days = 0]) =>
    DateTime(2026, 10, 5 + days, hour, minute);

OpeningStatus? _status(String raw, DateTime at) =>
    OpeningHours.parse(raw)?.status(at);

OpeningStatus _open([DateTime? closes]) =>
    OpeningStatus(open: true, change: closes);

OpeningStatus _closed([DateTime? opens]) =>
    OpeningStatus(open: false, change: opens);

void main() {
  test('the reference day is a Monday', () {
    expect(_mon(0).weekday, DateTime.monday);
  });

  test('24/7 is always open, with no closing time', () {
    expect(_status('24/7', _mon(3)), _open());
    expect(_status('Mo-Su 00:00-24:00', _mon(12, 0, 4)), _open());
  });

  group('a day range', () {
    const raw = 'Mo-Fr 08:00-18:00';

    test('open inside its hours, closing at their end', () {
      expect(_status(raw, _mon(10)), _open(_mon(18)));
    });

    test('closed before opening, opening the same day', () {
      expect(_status(raw, _mon(7, 59)), _closed(_mon(8)));
    });

    test('the end is not open any more', () {
      expect(_status(raw, _mon(18, 0, 4)), _closed(_mon(8, 0, 7)));
    });

    test('closed at the weekend, opening on Monday', () {
      expect(_status(raw, _mon(10, 0, 5)), _closed(_mon(8, 0, 7)));
    });
  });

  test('a day list', () {
    expect(
      _status('Mo,We 09:00-12:00', _mon(10, 0, 1)),
      _closed(_mon(9, 0, 2)),
    );
    expect(_status('Mo,We 09:00-12:00', _mon(10, 0, 2)), _open(_mon(12, 0, 2)));
  });

  test('a day range across the weekend', () {
    expect(_status('Fr-Mo 10:00-12:00', _mon(11, 0, 6)), _open(_mon(12, 0, 6)));
    expect(
      _status('Fr-Mo 10:00-12:00', _mon(11, 0, 1)),
      _closed(_mon(10, 0, 4)),
    );
  });

  test('several time ranges, with or without spaces', () {
    for (final raw in [
      'Mo-Fr 08:00-12:00,14:00-18:00',
      'Mo-Fr 08:00-12:00, 14:00-18:00',
    ]) {
      expect(_status(raw, _mon(11)), _open(_mon(12)), reason: raw);
      expect(_status(raw, _mon(13)), _closed(_mon(14)), reason: raw);
      expect(_status(raw, _mon(15)), _open(_mon(18)), reason: raw);
    }
  });

  test('a later rule replaces an earlier one for its days', () {
    const raw = 'Mo-Sa 08:00-18:00; Sa 08:00-12:00';
    expect(_status(raw, _mon(13, 0, 5)), _closed(_mon(8, 0, 7)));
    expect(_status(raw, _mon(13)), _open(_mon(18)));
  });

  test('off and closed close a day', () {
    for (final raw in [
      'Mo-Su 10:00-20:00; Tu off',
      'Mo-Su 10:00-20:00; Tu closed',
    ]) {
      expect(
        _status(raw, _mon(12, 0, 1)),
        _closed(_mon(10, 0, 2)),
        reason: raw,
      );
    }
    expect(_status('off', _mon(12)), _closed());
  });

  test('public holidays are left out', () {
    expect(_status('Mo-Fr 08:00-18:00; PH off', _mon(10)), _open(_mon(18)));
    expect(_status('Sa,PH 10:00-12:00', _mon(11, 0, 5)), _open(_mon(12, 0, 5)));
    // Nothing but holidays says nothing about today.
    expect(OpeningHours.parse('PH off'), isNull);
  });

  test('hours past midnight run into the next day', () {
    const raw = 'Mo-Su 18:00-02:00';
    expect(_status(raw, _mon(1, 0, 1)), _open(_mon(2, 0, 1)));
    expect(_status(raw, _mon(23)), _open(_mon(2, 0, 1)));
    expect(_status(raw, _mon(3, 0, 1)), _closed(_mon(18, 0, 1)));
  });

  test('times without days hold every day', () {
    expect(_status('08:00-18:00', _mon(9, 0, 6)), _open(_mon(18, 0, 6)));
  });

  test('a second rule after a comma adds to the first', () {
    const raw = 'Mo-Fr 08:00-12:00, Sa 09:00-11:00';
    expect(_status(raw, _mon(10)), _open(_mon(12)));
    expect(_status(raw, _mon(10, 0, 5)), _open(_mon(11, 0, 5)));
    expect(_status(raw, _mon(10, 0, 6)), _closed(_mon(8, 0, 7)));
  });

  test('anything it cannot read gives no status at all', () {
    for (final raw in [
      '',
      'Mo-Fr 08:00-18:00; Jan off',
      'sunrise-sunset',
      'Mo-Fr 08:00+',
      '"by appointment"',
      'Mon 08:00-18:00',
      'Mo-Fr',
      'SH off',
      'Mo-Fr 08:00-18:00 open',
      'Mo-Fr 25:00-26:00',
      'Mo-Fr 08:60-18:00',
      'Mo-Fr 08:00-08:00',
      'Mo-Fr 08:00-12:00 || "on request"',
    ]) {
      expect(OpeningHours.parse(raw), isNull, reason: raw);
    }
  });

  test('the rules as lines to show', () {
    expect(
      openingHoursLines('Mo-Fr 08:00-12:00,14:00-18:00; Sa 09:00-12:00;PH off'),
      <String>['Mo-Fr 08:00-12:00, 14:00-18:00', 'Sa 09:00-12:00', 'PH off'],
    );
  });
}
