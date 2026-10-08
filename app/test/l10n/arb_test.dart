import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the ARB files that Crowdin writes.
///
/// `app_en.arb` is the source; every other `app_<code>.arb` is a translation,
/// written with the English and refined in Crowdin. Such a file is safe to
/// merge when it declares the locale its name promises, carries every key the
/// English has (a missing one shows English in the translated app) and no key
/// the English lacks (a string nobody can see, or a leftover from a renamed
/// one), keeps every placeholder, and translates what is meant to be
/// translated: a value identical to the English is taken for a string that
/// was copied rather than translated, unless [sameAsEnglish] says why it may
/// stay.
void main() {
  final Directory dir = Directory('lib/l10n');
  final Map<String, Object?> source = jsonDecode(
    File('${dir.path}/app_en.arb').readAsStringSync(),
  ) as Map<String, Object?>;
  final Map<String, String> messages = <String, String>{
    for (final MapEntry<String, Object?> entry in source.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value! as String,
  };

  final List<File> translations =
      dir
          .listSync()
          .whereType<File>()
          .where(
            (f) => f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the English source is the template', () {
    expect(source['@@locale'], 'en');
  });

  test('every English message has a description for translators', () {
    final List<String> undescribed = <String>[
      for (final String key in messages.keys)
        if ((source['@$key'] as Map<String, Object?>?)?['description']
            case final Object? description
            when description is! String || description.trim().isEmpty)
          key,
    ];
    expect(undescribed, isEmpty);
  });

  test('the same-as-English allowlist names only English keys', () {
    expect(
      sameAsEnglish.keys.where((key) => !messages.containsKey(key)),
      isEmpty,
    );
  });

  test('placeholders are read from ICU messages', () {
    expect(icuArguments('Routing failed: {message}'), <String>{'message'});
    expect(
      icuArguments(
        '{count, plural, =1{1 ride} other{{count} rides in {area}}}',
      ),
      <String>{'count', 'area'},
    );
    expect(
      icuArguments("{kind, select, a{A} other{'{literal}' {name}}}"),
      <String>{'kind', 'name'},
    );
  });

  for (final File file in translations) {
    final String name = file.uri.pathSegments.last;
    final String locale = name
        .substring('app_'.length, name.length - '.arb'.length)
        .replaceAll('-', '_');

    group(name, () {
      final Map<String, Object?> arb =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

      test('declares the locale in its file name', () {
        expect(arb['@@locale'], locale);
      });

      test('has no key the English source does not have', () {
        final Iterable<String> unknown = arb.keys.where((key) {
          if (key.startsWith('@@')) return false;
          final String message = key.startsWith('@') ? key.substring(1) : key;
          return !source.containsKey(message);
        });
        expect(unknown, isEmpty);
      });

      test('has every key of the English source', () {
        final List<String> missing = <String>[
          for (final String key in messages.keys)
            if (arb[key] is! String || (arb[key]! as String).trim().isEmpty)
              key,
        ];
        expect(missing, isEmpty, reason: 'missing or empty in $name');
      });

      test('keeps the placeholders of every English message', () {
        final List<String> wrong = <String>[
          for (final MapEntry<String, String> entry in messages.entries)
            if (arb[entry.key] case final String translated)
              if (!_sameSet(
                icuArguments(entry.value),
                icuArguments(translated),
              ))
                '${entry.key}: English ${icuArguments(entry.value)}, '
                    '$locale ${icuArguments(translated)}',
        ];
        expect(wrong, isEmpty);
      });

      test('translates every message that is not allowed to stay English', () {
        final List<String> copied = <String>[
          for (final MapEntry<String, String> entry in messages.entries)
            if (arb[entry.key] == entry.value &&
                _hasWords(entry.value) &&
                !sameAsEnglish.containsKey(entry.key))
              '${entry.key}: "${entry.value}"',
        ];
        expect(
          copied,
          isEmpty,
          reason:
              'identical to the English: translate it, or add the key to '
              'sameAsEnglish in this test with the reason it stays',
        );
      });
    });
  }
}

/// Messages a translation may leave exactly as the English, and why.
///
/// A value without letters once its placeholders are taken out
/// (`{distance} · {elevation}`, `{value} %`) needs no entry. Everything here is
/// a brand or product name, a unit or abbreviation that is the same across the
/// languages the app ships, or a word the target languages borrowed. A
/// language that does translate one of these is free to.
const Map<String, String> sameAsEnglish = <String, String>{
  // Brand, product and service names.
  'appName': 'brand',
  'poweredByStrava': "Strava's attribution, required in English",
  'serviceAppleMaps': 'product name',
  'serviceGoogleMaps': 'product name',
  'serviceOpenStreetMap': 'project name',
  'serviceStrava': 'brand',
  'serviceRwgps': 'brand',
  'connectionsPlusTitle': 'product name (Velorki Plus)',
  'plusTitle': 'product name (Velorki Plus)',
  'mapAttributionOpenFreeMap': 'project name',
  'mapAttributionCyclosm': 'project name',
  'settingsSensorsAppleHealth': 'product name',
  'settingsSensorsHealthConnect': 'product name',
  'settingsSensorsAppleWatch': 'product name',
  'accentVolt': 'name of a colour preset',
  'voiceQualityPremium': "the platform's own name for the voice tier",
  // File formats.
  'importFormatGpx': 'file format',
  'importFormatFit': 'file format',
  'importFormatTcx': 'file format',
  // Units and their symbols.
  'unitM': 'unit symbol',
  'unitKm': 'unit symbol',
  'unitFt': 'unit symbol',
  'unitMi': 'unit symbol',
  'unitKmh': 'unit symbol',
  'unitMph': 'unit symbol',
  'unitBpm': 'unit symbol',
  'unitWatts': 'unit symbol',
  'unitKcal': 'unit symbol',
  'unitCelsius': 'unit symbol',
  'valueHoursMinutes': 'unit symbols',
  'valueMinutes': 'unit symbol',
  'navDistanceMetres': 'unit symbol',
  'navDistanceKm': 'unit symbol',
  'navDistanceFeet': 'unit symbol',
  'navDistanceMiles': 'unit symbol',
  'settingsTurnLeadValue': 'unit symbol',
  'bleSignal': 'unit symbol',
  'bleWheelCircumferenceUnit': 'unit symbol',
  'settingsRiderWeightKg': 'unit symbol',
  'settingsRiderWeightLb': 'unit symbol',
  'settingsRiderMaxHeartRateUnit': 'unit symbol',
  'settingsRiderThresholdPowerUnit': 'unit symbol',
  'rideClimbVam': 'unit symbol',
  'rideHeartRateZoneLabel': 'Z for zone, the training abbreviation',
  'ridePowerZoneTopLabel': 'Z for zone, the training abbreviation',
  // Words the target languages use as they are.
  'settingsVersion': 'same word',
  'profileGravel': 'bike type, borrowed',
  'profileMtb': 'abbreviation',
  'plannerRouteNameLabel': 'same word',
  'plannerPointName': 'same word',
  'importNameLabel': 'same word',
  'plannerDefaultRouteName': 'same word',
  'placeCardDetails': 'same word',
  'searchKindRestaurant': 'same word',
  'searchKindPark': 'same word',
  'searchKindMuseum': 'same word',
  'searchKindHotel': 'same word',
  'searchKindHostel': 'same word',
  'routeDetailExport': 'same word',
  'routeDetailLink': 'same word',
  'importTitle': 'same word',
  'importKindRoute': 'same word',
  'rideShowRoute': 'same word',
  'importTrackNumber': 'same word',
  'recordingPause': 'same word',
  'cueSheetStart': 'same word',
  'rideClimbStartColumn': 'same word',
  'statMaxSpeed': 'abbreviation',
  'rideSplitColumn': 'cycling term, borrowed',
  'rideHighlightSplit': 'cycling term, borrowed',
  'appearanceModeSystem': 'same word',
  'languageSystem': 'same word',
  'unitsImperial': 'same word',
  'offlineTitle': 'same word',
  'settingsRouting': 'borrowed',
  'settingsNavigation': 'same word',
  'gpsPrecisionNormal': 'same word',
  'navTurnIn': '"in" is the same word',
  // Country and language names spelled the same way.
  'regionCL': 'same name',
  'regionCN': 'same name',
  'regionIL': 'same name',
  'regionIR': 'same name',
  'regionJP': 'same name',
  'regionMY': 'same name',
  'regionNG': 'same name',
  'regionPT': 'same name',
  'regionTH': 'same name',
  'regionTR': 'same name',
  'regionTW': 'same name',
  'regionUA': 'same name',
  'regionVN': 'same name',
  'languageBho': 'same name',
  'languageHi': 'same name',
  'languageKn': 'same name',
  'languageMr': 'same name',
  'languageTa': 'same name',
  'languageTe': 'same name',
  'languageTh': 'same name',
};

/// Whether [message] has letters once its placeholders are taken out.
bool _hasWords(String message) {
  final String text = message.replaceAll(RegExp(r'\{[^{}]*\}'), '');
  return RegExp(r'\p{L}', unicode: true).hasMatch(text);
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// The argument names of the ICU message [message].
///
/// `{name}` is an argument; `{count, plural, =1{…} other{…}}` is the argument
/// `count`, and the branch texts are read for further arguments but their
/// words are not. Text in single quotes is ICU's escape and is skipped.
Set<String> icuArguments(String message) {
  final Set<String> out = <String>{};
  _readText(message, 0, out, topLevel: true);
  return out;
}

/// Reads message text from [start] until an unmatched `}` (or the end), and
/// returns the index after it.
int _readText(String s, int start, Set<String> out, {bool topLevel = false}) {
  var i = start;
  while (i < s.length) {
    final String c = s[i];
    if (c == "'") {
      final int end = s.indexOf("'", i + 1);
      if (end == i + 1) {
        i += 2; // '' is a literal quote
        continue;
      }
      // A quote only escapes when it is followed by a syntax character.
      if (end > 0 && i + 1 < s.length && '{}#|'.contains(s[i + 1])) {
        i = end + 1;
        continue;
      }
      i++;
    } else if (c == '{') {
      i = _readArgument(s, i + 1, out);
    } else if (c == '}') {
      if (topLevel) {
        i++;
        continue;
      }
      return i + 1;
    } else {
      i++;
    }
  }
  return i;
}

/// Reads an argument after its `{` and returns the index after its `}`.
int _readArgument(String s, int start, Set<String> out) {
  var i = start;
  final StringBuffer name = StringBuffer();
  while (i < s.length && s[i] != ',' && s[i] != '}') {
    name.write(s[i]);
    i++;
  }
  out.add(name.toString().trim());
  if (i >= s.length) return i;
  if (s[i] == '}') return i + 1;
  // `, type` and, for plural/select, `, branches`.
  i++;
  final StringBuffer type = StringBuffer();
  while (i < s.length && s[i] != ',' && s[i] != '}') {
    type.write(s[i]);
    i++;
  }
  if (i >= s.length) return i;
  if (s[i] == '}') return i + 1;
  i++;
  // Branches: `selector {text}` repeated, until the argument's `}`.
  while (i < s.length) {
    final String c = s[i];
    if (c == '{') {
      i = _readText(s, i + 1, out);
    } else if (c == '}') {
      return i + 1;
    } else {
      i++;
    }
  }
  return i;
}
