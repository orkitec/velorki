import '../../../core/geo/power_model.dart';
import 'rider_profile.dart';

/// The [PowerModel] for a rider of [riderKg] on a [bike] of [bikeKg]: the
/// total mass and the drag and rolling figures the bike type stands for.
///
/// Published CdA for a rider on the hoods runs 0.30–0.40 m²; Crr on smooth
/// asphalt 0.004–0.006, on gravel above 0.012.
PowerModel powerModelForBike(
  RiderBike bike, {
  required double riderKg,
  required double bikeKg,
}) {
  final (cdA, crr) = switch (bike) {
    // On the hoods, good road tyres: the low end of both ranges.
    RiderBike.road => (0.32, 0.005),
    // More upright, wider tyres, often unpaved: the middle of the CdA range,
    // a Crr between asphalt and gravel.
    RiderBike.touring => (0.38, 0.008),
    // Upright, knobbly tyres: the top of the CdA range, a gravel Crr.
    RiderBike.mountain => (0.42, 0.012),
  };
  return PowerModel(massKg: riderKg + bikeKg, cdA: cdA, crr: crr);
}
