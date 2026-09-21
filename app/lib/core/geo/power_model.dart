import 'dart:math' as math;

/// Martin et al. 1998: what the rider must put into the pedals to move a
/// bike of total mass [massKg] at speed on a slope, with no wind.
///
/// The three figures are all the model knows about the rider and the bike;
/// what a bike type is worth in drag and rolling resistance is decided where
/// the bike type lives, not here.
class PowerModel {
  /// Creates a model.
  const PowerModel({
    required this.massKg,
    required this.cdA,
    required this.crr,
  });

  /// Rider and bike together, in kilograms.
  final double massKg;

  /// Drag area, the drag coefficient times the frontal area, in m².
  final double cdA;

  /// Rolling resistance coefficient, dimensionless.
  final double crr;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PowerModel &&
          other.massKg == massKg &&
          other.cdA == cdA &&
          other.crr == crr;

  @override
  int get hashCode => Object.hash(massKg, cdA, crr);

  @override
  String toString() =>
      'PowerModel(${massKg.toStringAsFixed(1)} kg, cdA $cdA, crr $crr)';
}

/// The share of the pedal power that reaches the road: 2.5 % is lost in the
/// chain and the bearings.
const double drivetrainEfficiency = 0.975;

/// Standard gravity, m/s².
const double gravityMps2 = 9.8067;

/// Air density at [elevationM]: 1.225 · exp(−0.0001186 · h) kg/m³, the sea
/// level standard thinned by the barometric formula.
double airDensityAt(double elevationM) =>
    1.225 * math.exp(-0.0001186 * elevationM);

/// Pedal power in watts for one leg: speed [vMps], slope [grade] (rise over
/// run), acceleration [aMps2], at [elevationM]. Never below zero: coasting
/// and braking are no work for the rider.
///
/// P = (m g sin θ + m a + crr m g cos θ + ½ ρ cdA v²) · v / η, θ = atan(grade).
double pedalPowerW(
  PowerModel model, {
  required double vMps,
  required double grade,
  required double aMps2,
  required double elevationM,
}) {
  final theta = math.atan(grade);
  final weight = model.massKg * gravityMps2;
  final force =
      weight * math.sin(theta) +
      model.massKg * aMps2 +
      model.crr * weight * math.cos(theta) +
      0.5 * airDensityAt(elevationM) * model.cdA * vMps * vMps;
  final power = force * vMps / drivetrainEfficiency;
  return power < 0 ? 0 : power;
}
