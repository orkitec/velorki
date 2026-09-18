import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/domain/ride_naming.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A local start time on the day the fixtures use.
DateTime at(int hour, [int minute = 0]) => DateTime(2026, 9, 12, hour, minute);

/// Funchal, and a point [meters] north of it.
const LatLng funchal = LatLng(32.6669, -16.9241);
LatLng north(double meters) =>
    LatLng(funchal.lat + meters / 111194.9266, funchal.lon);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  group('the time of day follows Strava\'s buckets', () {
    test('every boundary falls on the side it is named for', () {
      expect(rideTimeOfDay(at(3, 59)), RideTimeOfDay.night);
      expect(rideTimeOfDay(at(4)), RideTimeOfDay.morning);
      expect(rideTimeOfDay(at(10, 59)), RideTimeOfDay.morning);
      expect(rideTimeOfDay(at(11)), RideTimeOfDay.lunch);
      expect(rideTimeOfDay(at(13, 59)), RideTimeOfDay.lunch);
      expect(rideTimeOfDay(at(14)), RideTimeOfDay.afternoon);
      expect(rideTimeOfDay(at(16, 59)), RideTimeOfDay.afternoon);
      expect(rideTimeOfDay(at(17)), RideTimeOfDay.evening);
      expect(rideTimeOfDay(at(20, 59)), RideTimeOfDay.evening);
      expect(rideTimeOfDay(at(21)), RideTimeOfDay.night);
      expect(rideTimeOfDay(at(0)), RideTimeOfDay.night);
    });

    test('each bucket names a ride in English', () {
      String name(int hour) => defaultRideName(en, startedAt: at(hour));
      expect(name(3), 'Night ride');
      expect(name(4), 'Morning ride');
      expect(name(11), 'Lunch ride');
      expect(name(14), 'Afternoon ride');
      expect(name(17), 'Evening ride');
      expect(name(21), 'Night ride');
    });

    test('each bucket compounds into one German word', () {
      String ride(int hour) => defaultRideName(de, startedAt: at(hour));
      String loop(int hour) =>
          defaultRideName(de, startedAt: at(hour), isLoop: true);
      expect(ride(3), 'Nachtfahrt');
      expect(ride(4), 'Morgenfahrt');
      expect(ride(11), 'Mittagsfahrt');
      expect(ride(14), 'Nachmittagsfahrt');
      expect(ride(17), 'Abendfahrt');
      expect(loop(4), 'Morgenrunde');
      expect(loop(11), 'Mittagsrunde');
      expect(loop(14), 'Nachmittagsrunde');
      expect(loop(17), 'Abendrunde');
      expect(loop(21), 'Nachtrunde');
    });
  });

  group('a loop is a ride that ends where it began', () {
    test('900 m apart is a loop, 1.1 km apart is not', () {
      expect(isRideLoop(funchal, north(900)), isTrue);
      expect(isRideLoop(funchal, north(1100)), isFalse);
      expect(isRideLoop(funchal, funchal), isTrue);
    });

    test('an unknown end is not a loop', () {
      expect(isRideLoop(funchal, null), isFalse);
      expect(isRideLoop(null, null), isFalse);
    });

    test('0.9 km back to the start is named a loop, 1.1 km a journey', () {
      String name(double meters) => defaultRideName(
        en,
        startedAt: at(9),
        startPlace: 'Funchal',
        endPlace: meters > 1000 ? 'Monte' : 'Funchal',
        isLoop: isRideLoop(funchal, north(meters)),
      );
      expect(name(900), 'Morning loop from Funchal');
      expect(name(1100), 'Morning ride from Funchal to Monte');
    });
  });

  group('the places a ride ran between', () {
    test('both known, in both languages', () {
      expect(
        defaultRideName(
          en,
          startedAt: at(9),
          startPlace: 'Funchal',
          endPlace: 'Monte',
        ),
        'Morning ride from Funchal to Monte',
      );
      expect(
        defaultRideName(
          de,
          startedAt: at(9),
          startPlace: 'Funchal',
          endPlace: 'Monte',
        ),
        'Morgenfahrt von Funchal nach Monte',
      );
    });

    test('a loop from a known place, in both languages', () {
      expect(
        defaultRideName(
          en,
          startedAt: at(9),
          startPlace: 'Funchal',
          endPlace: 'Funchal',
          isLoop: true,
        ),
        'Morning loop from Funchal',
      );
      expect(
        defaultRideName(
          de,
          startedAt: at(9),
          startPlace: 'Funchal',
          endPlace: 'Funchal',
          isLoop: true,
        ),
        'Morgenrunde ab Funchal',
      );
    });

    test('a known start and an unknown end', () {
      expect(
        defaultRideName(en, startedAt: at(18), startPlace: 'Funchal'),
        'Evening ride from Funchal',
      );
      expect(
        defaultRideName(de, startedAt: at(18), startPlace: 'Funchal'),
        'Abendfahrt ab Funchal',
      );
    });

    test('no place at all keeps the loop and the ride apart', () {
      expect(
        defaultRideName(en, startedAt: at(12), isLoop: true),
        'Lunch loop',
      );
      expect(defaultRideName(en, startedAt: at(12)), 'Lunch ride');
      expect(
        defaultRideName(de, startedAt: at(12), isLoop: true),
        'Mittagsrunde',
      );
      expect(defaultRideName(de, startedAt: at(12)), 'Mittagsfahrt');
    });

    test('an unknown start hides a known end', () {
      expect(
        defaultRideName(en, startedAt: at(22), endPlace: 'Monte'),
        'Night ride',
      );
    });

    test('a wandering ride back into its own town is named once', () {
      expect(
        defaultRideName(
          en,
          startedAt: at(9),
          startPlace: 'Funchal',
          endPlace: 'Funchal',
        ),
        'Morning ride from Funchal',
      );
    });

    test('blank place names count as no place', () {
      expect(
        defaultRideName(
          en,
          startedAt: at(9),
          startPlace: '  ',
          endPlace: 'Monte',
        ),
        'Morning ride',
      );
    });
  });

  group('a followed route names the ride', () {
    test('the route wins over the time and the places', () {
      expect(
        defaultRideName(
          en,
          startedAt: at(9),
          routeName: 'Levada do Norte',
          startPlace: 'Funchal',
          endPlace: 'Monte',
        ),
        'Levada do Norte',
      );
      expect(
        defaultRideName(
          de,
          startedAt: at(9),
          routeName: 'Levada do Norte',
          startPlace: 'Funchal',
          isLoop: true,
        ),
        'Levada do Norte',
      );
    });

    test('a blank route name falls back to the scheme', () {
      expect(
        defaultRideName(
          en,
          startedAt: at(9),
          routeName: '   ',
          startPlace: 'Funchal',
          isLoop: true,
        ),
        'Morning loop from Funchal',
      );
    });
  });
}
