import '../../../core/units/units.dart';

/// How long one split of a ride is, in the rider's units.
///
/// [auto] is the default and picks the length from the ride's distance, so
/// the table stays short whatever the ride: a kilometre (or a mile) up to
/// [autoFiveFromUnits] of them, five up to [autoTenFromUnits], ten beyond.
/// The other three are the rider's override.
enum SplitLength {
  /// Chosen from the ride's distance.
  auto(0),

  /// One kilometre or one mile.
  one(1),

  /// Five kilometres or five miles.
  five(5),

  /// Ten kilometres or ten miles.
  ten(10);

  const SplitLength(this.units);

  /// How many kilometres or miles one split is; `0` for [auto].
  final int units;

  /// The length named [name], or [auto] when the name is unknown.
  static SplitLength fromName(String? name) => SplitLength.values.firstWhere(
    (length) => length.name == name,
    orElse: () => auto,
  );
}

/// A ride longer than this many kilometres or miles gets five-unit splits.
const double autoFiveFromUnits = 30;

/// A ride longer than this many kilometres or miles gets ten-unit splits.
const double autoTenFromUnits = 150;

/// One kilometre or one mile in metres, whichever [system] counts in.
double splitUnitMetres(UnitSystem system) =>
    system == UnitSystem.imperial ? metersPerMile : metersPerKilometer;

/// How many kilometres or miles one split of a ride [distanceM] long is, with
/// [choice] applied.
int splitUnits(SplitLength choice, UnitSystem system, double distanceM) {
  if (choice != SplitLength.auto) return choice.units;
  final units = distanceM / splitUnitMetres(system);
  if (units <= autoFiveFromUnits) return 1;
  if (units <= autoTenFromUnits) return 5;
  return 10;
}

/// The length of one split in metres for a ride [distanceM] long.
double splitLengthMetres(
  SplitLength choice,
  UnitSystem system,
  double distanceM,
) => splitUnits(choice, system, distanceM) * splitUnitMetres(system);
