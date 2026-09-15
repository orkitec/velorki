/// Distances, speeds and heights in the units the rider reads them in.
///
/// Pure arithmetic: everything here works on plain numbers and says which
/// unit the number came out in. Putting the unit label around the figure is
/// the presentation layer's job, because the label is translated.
library;

/// Which units a rider reads distances, speeds and heights in.
enum UnitSystem {
  /// Metres, kilometres and km/h.
  metric,

  /// Feet, miles and mph.
  imperial;

  /// The system named [name], or [metric] when the name is unknown.
  static UnitSystem fromName(String? name) => UnitSystem.values.firstWhere(
    (system) => system.name == name,
    orElse: () => metric,
  );
}

/// Metres in a kilometre.
const double metersPerKilometer = 1000;

/// Metres in a statute mile.
const double metersPerMile = 1609.344;

/// Metres in a foot.
const double metersPerFoot = 0.3048;

/// Below this many miles a distance reads in feet rather than in miles.
const double _milesBelowWhichFeet = 0.1;

/// The unit a [Measure] came out in.
enum MeasureUnit {
  /// Metres.
  meters,

  /// Kilometres.
  kilometers,

  /// Feet.
  feet,

  /// Miles.
  miles,

  /// Kilometres per hour.
  kilometersPerHour,

  /// Miles per hour.
  milesPerHour,
}

/// A figure ready to be shown: the number, the unit it is in, and how many
/// decimal places it should carry.
class Measure {
  /// Creates the figure.
  const Measure(this.value, this.unit, {this.decimals = 0});

  /// The number, already converted into [unit].
  final double value;

  /// What [value] is measured in.
  final MeasureUnit unit;

  /// How many decimal places the number should be shown with.
  final int decimals;

  @override
  bool operator ==(Object other) =>
      other is Measure &&
      other.value == value &&
      other.unit == unit &&
      other.decimals == decimals;

  @override
  int get hashCode => Object.hash(value, unit, decimals);

  @override
  String toString() =>
      'Measure(${value.toStringAsFixed(decimals)} ${unit.name})';
}

/// A distance for the statistics rows.
///
/// Metric reads in metres below a kilometre and in kilometres with one
/// decimal above it. Imperial reads in feet below a tenth of a mile — rounded
/// to ten feet, because the last digit of a figure that short would only
/// flicker — and in miles with one decimal above it.
Measure formatDistance(UnitSystem system, double meters) {
  if (system == UnitSystem.metric) {
    if (meters.abs() < metersPerKilometer) {
      return Measure(meters, MeasureUnit.meters);
    }
    return Measure(
      meters / metersPerKilometer,
      MeasureUnit.kilometers,
      decimals: 1,
    );
  }
  final miles = meters / metersPerMile;
  if (miles.abs() < _milesBelowWhichFeet) {
    return Measure(roundToTenFeet(meters), MeasureUnit.feet);
  }
  return Measure(miles, MeasureUnit.miles, decimals: 1);
}

/// A speed, with one decimal either way.
Measure formatSpeed(UnitSystem system, double metersPerSecond) =>
    system == UnitSystem.metric
    ? Measure(metersPerSecond * 3.6, MeasureUnit.kilometersPerHour, decimals: 1)
    : Measure(
        metersPerSecond * 3600 / metersPerMile,
        MeasureUnit.milesPerHour,
        decimals: 1,
      );

/// A height, in whole metres or whole feet.
Measure formatElevation(UnitSystem system, double meters) =>
    system == UnitSystem.metric
    ? Measure(meters, MeasureUnit.meters)
    : Measure(
        elevationToDisplay(system, meters).roundToDouble(),
        MeasureUnit.feet,
      );

/// [meters] in the big distance unit of [system]: kilometres or miles.
///
/// For sliders and charts, which work on the bare number and put the unit in
/// their own label.
double distanceToDisplay(UnitSystem system, double meters) =>
    meters / (system == UnitSystem.metric ? metersPerKilometer : metersPerMile);

/// The other way round: a slider's kilometres or miles back into metres.
double displayToMeters(UnitSystem system, double value) =>
    value * (system == UnitSystem.metric ? metersPerKilometer : metersPerMile);

/// [meters] in the height unit of [system]: metres or feet.
double elevationToDisplay(UnitSystem system, double meters) =>
    system == UnitSystem.metric ? meters : meters / metersPerFoot;

/// [meters] in feet, rounded to the nearest ten.
double roundToTenFeet(double meters) =>
    (meters / metersPerFoot / 10).roundToDouble() * 10;

/// [meters] in feet, rounded to the nearest hundred.
///
/// The spoken warning before a turn: "in nine hundred and eighty-four feet"
/// is not something anyone says out loud.
double roundToHundredFeet(double meters) =>
    (meters / metersPerFoot / 100).roundToDouble() * 100;
