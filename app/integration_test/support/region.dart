/// Where the suite plans its routes.
///
/// The emulator's virtual GPS and the rd5 tile on the device have to agree
/// with the coordinates the tests use, and the two setups differ:
///
/// * locally the mirror serves the New York tile `W75_N40` and the emulator
///   sits at Sakura Park (`adb emu geo fix -73.9645 40.8153`);
/// * CI serves the frozen oracle tile `W20_N30` and puts the emulator in
///   Funchal, because that is the tile the BRouter oracle release pins.
///
/// The region is chosen with `--dart-define=VELORKI_ITEST_REGION=madeira`;
/// anything else (including the default) means New York.
library;

import 'package:velorki_geo/velorki_geo.dart';

/// The coordinates one run of the suite works with.
class ItestRegion {
  const ItestRegion({
    required this.name,
    required this.tile,
    required this.start,
    required this.via,
    required this.end,
    required this.searchQuery,
    required this.searchPlace,
    required this.searchCity,
    required this.searchResult,
  });

  /// `nyc` or `madeira`, only for messages.
  final String name;

  /// The rd5 tile that has to be on the device before anything routes.
  final String tile;

  /// Where the fake position source puts the rider; matches `adb emu geo fix`.
  final LatLng start;

  /// A point between [start] and [end], for the multi-waypoint plans.
  final LatLng via;

  /// The far end of the plans.
  final LatLng end;

  /// What the search test types into the field.
  final String searchQuery;

  /// The name of the place the scripted geocoder answers with.
  final String searchPlace;

  /// The city of that place.
  final String searchCity;

  /// Where that place is; the destination of the search test's plan.
  final LatLng searchResult;
}

/// New York: the `W75_N40` tile, around Sakura Park and Central Park.
const ItestRegion _nyc = ItestRegion(
  name: 'nyc',
  tile: 'W75_N40',
  start: LatLng(40.8153, -73.9645),
  via: LatLng(40.7995, -73.9580),
  end: LatLng(40.7829, -73.9654),
  searchQuery: 'Central Park',
  searchPlace: 'Central Park',
  searchCity: 'New York',
  searchResult: LatLng(40.7829, -73.9654),
);

/// Madeira: the `W20_N30` tile the frozen oracle release serves, from Funchal
/// to Machico. Same coordinates the two older integration tests already use.
const ItestRegion _madeira = ItestRegion(
  name: 'madeira',
  tile: 'W20_N30',
  start: LatLng(32.650, -16.920),
  via: LatLng(32.700, -16.850),
  end: LatLng(32.720, -16.770),
  searchQuery: 'Machico',
  searchPlace: 'Machico',
  searchCity: 'Madeira',
  searchResult: LatLng(32.720, -16.770),
);

const String _regionName = String.fromEnvironment(
  'VELORKI_ITEST_REGION',
  defaultValue: 'nyc',
);

/// The region this build of the suite runs against.
const ItestRegion region = _regionName == 'madeira' ? _madeira : _nyc;
