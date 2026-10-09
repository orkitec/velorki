import 'dart:io';

/// The app's lookup table, which the tiles are built against.
List<String> lookupsLines() =>
    File('../../assets/brouter/profiles/lookups.dat').readAsLinesSync();

/// The directory with the oracle's committed tiles (Madeira is W20_N30).
final Directory oracleTiles = Directory('../../../tools/brouter-oracle/tiles');
