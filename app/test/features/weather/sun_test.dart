import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/weather/domain/sun.dart';

void main() {
  group('sunDay', () {
    test('Berlin at midsummer: up before 3 UTC, down after 19 UTC', () {
      final sun = sunDay(DateTime.utc(2026, 6, 21), 52.52, 13.40);
      // Published: 04:43 and 21:33 CEST, that is 02:43 and 19:33 UTC.
      expect(
        sun.rise!.difference(DateTime.utc(2026, 6, 21, 2, 43)).inMinutes.abs(),
        lessThan(5),
      );
      expect(
        sun.set!.difference(DateTime.utc(2026, 6, 21, 19, 33)).inMinutes.abs(),
        lessThan(5),
      );
    });

    test('the equator at the equinox: about twelve hours of day', () {
      final sun = sunDay(DateTime.utc(2026, 3, 20), 0, 0);
      final day = sun.set!.difference(sun.rise!);
      expect(day.inMinutes, inInclusiveRange(12 * 60, 12 * 60 + 10));
    });

    test('Tromsø: midnight sun in June, polar night in December', () {
      expect(sunDay(DateTime.utc(2026, 6, 21), 69.65, 18.96).allDay, isTrue);
      final dark = sunDay(DateTime.utc(2026, 12, 21), 69.65, 18.96);
      expect(dark.allDay, isFalse);
      expect(dark.rise, isNull);
    });
  });

  group('inDaylight', () {
    test('a ride in the afternoon is, one into the night is not', () {
      final noon = DateTime.utc(2026, 10, 11, 11);
      expect(
        inDaylight(noon, noon.add(const Duration(hours: 2)), 50.94, 6.96),
        isTrue,
      );
      final dusk = DateTime.utc(2026, 10, 11, 16);
      expect(
        inDaylight(dusk, dusk.add(const Duration(hours: 2)), 50.94, 6.96),
        isFalse,
      );
      final night = DateTime.utc(2026, 10, 11, 2);
      expect(
        inDaylight(night, night.add(const Duration(hours: 1)), 50.94, 6.96),
        isFalse,
      );
    });

    test('far east, the local day decides, not the UTC date', () {
      // 23:00 UTC is 08:00 the next morning in Tokyo.
      final morning = DateTime.utc(2026, 10, 10, 23);
      expect(
        inDaylight(
          morning,
          morning.add(const Duration(hours: 2)),
          35.68,
          139.69,
        ),
        isTrue,
      );
    });
  });
}
