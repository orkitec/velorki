import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/domain/search_group.dart';
import 'package:velorki/features/search/domain/search_kinds.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

void main() {
  /// The one words a rider types for the transport kinds and the tube
  /// machines, in each language, and the kinds each asks for.
  const words = <String, Map<String, Set<String>>>{
    'en': <String, Set<String>>{
      'bus': <String>{'bus_stop'},
      'Bus stop': <String>{'bus_stop'},
      'tram': <String>{'tram_stop'},
      'streetcar': <String>{'tram_stop'},
      'train': <String>{'station'},
      'ferry': <String>{'ferry_terminal'},
      'inner tube': <String>{'bicycle_tube_vending'},
      'tube vending': <String>{'bicycle_tube_vending'},
    },
    'de': <String, Set<String>>{
      'Bus': <String>{'bus_stop'},
      'Bushaltestelle': <String>{'bus_stop'},
      'Haltestelle': <String>{'bus_stop', 'tram_stop'},
      'Tram': <String>{'tram_stop'},
      'Straßenbahn': <String>{'tram_stop'},
      'Zug': <String>{'station'},
      'Bahn': <String>{'station'},
      'Fähre': <String>{'ferry_terminal'},
      'Schlauch': <String>{'bicycle_tube_vending'},
      'Schlauchautomat': <String>{'bicycle_tube_vending'},
    },
    'fr': <String, Set<String>>{
      'bus': <String>{'bus_stop'},
      'tram': <String>{'tram_stop'},
      'tramway': <String>{'tram_stop'},
      'train': <String>{'station'},
      'ferry': <String>{'ferry_terminal'},
      'bac': <String>{'ferry_terminal'},
      'arrêt': <String>{'bus_stop', 'tram_stop'},
      'chambre à air': <String>{'bicycle_tube_vending'},
    },
    'es': <String, Set<String>>{
      'autobús': <String>{'bus_stop'},
      'bus': <String>{'bus_stop'},
      'tranvía': <String>{'tram_stop'},
      'tren': <String>{'station'},
      'ferry': <String>{'ferry_terminal'},
      'transbordador': <String>{'ferry_terminal'},
      'parada': <String>{'bus_stop', 'tram_stop'},
      'cámara de aire': <String>{'bicycle_tube_vending'},
    },
    'it': <String, Set<String>>{
      'autobus': <String>{'bus_stop'},
      'bus': <String>{'bus_stop'},
      'tram': <String>{'tram_stop'},
      'treno': <String>{'station'},
      'traghetto': <String>{'ferry_terminal'},
      'fermata': <String>{'bus_stop', 'tram_stop'},
      "camera d'aria": <String>{'bicycle_tube_vending'},
    },
    'nl': <String, Set<String>>{
      'bus': <String>{'bus_stop'},
      'tram': <String>{'tram_stop'},
      'halte': <String>{'bus_stop', 'tram_stop'},
      'trein': <String>{'station'},
      'veerboot': <String>{'ferry_terminal'},
      'pont': <String>{'ferry_terminal'},
      'binnenband': <String>{'bicycle_tube_vending'},
    },
  };

  for (final MapEntry(key: language, value: asked) in words.entries) {
    group(language, () {
      final l10n = lookupAppLocalizations(Locale(language));
      final table = localisedKindKeywords(l10n);

      test('one word asks for the nearest of its kind', () {
        for (final MapEntry(key: word, value: kinds) in asked.entries) {
          expect(
            kindsForKeyword(word, table).toSet(),
            kinds,
            reason: '"$word" in $language',
          );
        }
      });

      test('a name that holds such a word stays a name search', () {
        for (final name in <String>[
          'Busch',
          'Buschgasse',
          'Bahnhofstraße',
          'Trainstraße',
          'Tramstraße',
          'bus marktplatz',
          'Zugspitze',
        ]) {
          expect(kindsForKeyword(name, table), isEmpty, reason: name);
        }
      });

      test('the new kinds have a label and a group', () {
        for (final kind in <String>[
          'bus_stop',
          'tram_stop',
          'bicycle_tube_vending',
        ]) {
          expect(gazetteerPoiKindLabel(l10n, kind), isNotNull, reason: kind);
          expect(searchGroupOfPoiKind[kind], isNotNull, reason: kind);
          expect(searchPoiKinds, contains(kind));
        }
      });
    });
  }

  test('the stops are found by their kind only', () {
    expect(kindSearchOnlyPoiKinds, <String>{'bus_stop', 'tram_stop'});
    expect(searchGroupOfPoiKind['bus_stop'], SearchGroup.transport);
    expect(searchGroupOfPoiKind['tram_stop'], SearchGroup.transport);
    expect(
      searchGroupOfPoiKind['bicycle_tube_vending'],
      SearchGroup.cyclingStops,
    );
  });
}
