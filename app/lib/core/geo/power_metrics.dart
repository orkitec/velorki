import 'dart:math' as math;

/// One power reading and when it was taken, in whole seconds from wherever
/// the series starts counting.
typedef PowerSample = ({int atSeconds, int watts});

/// How long the rolling mean of the normalised power runs over: the body
/// answers a change of effort over about this long, so a thirty second surge
/// weighs what it costs rather than what it averages.
const int normalizedPowerWindowS = 30;

/// The longest silence of the meter the series is held across: a dropped
/// packet or two is bridged with the last reading, a stop is not.
const int normalizedPowerGapS = 5;

/// How many zones [powerZoneOf] sorts a reading into.
const int powerZoneCount = 7;

/// The lower bound of each power zone as a share of the threshold power,
/// [powerZoneCount] entries: zone 1 takes everything below 55 %, zone 7
/// everything from 150 %.
const List<int> powerZoneBoundsPercent = <int>[0, 55, 75, 90, 105, 120, 150];

/// The normalised power of [samples] in watts: the power resampled onto a
/// one second grid, the [normalizedPowerWindowS] rolling mean of that, each
/// mean raised to the fourth power, those averaged, and the fourth root of
/// the average. A steady ride comes out at its mean; a ride of surges and
/// rests comes out higher, which is what the legs felt.
///
/// Each reading is held until the next one; a gap longer than
/// [normalizedPowerGapS] is not bridged and starts a new series, and the
/// windows never straddle one. `null` when no series is [normalizedPowerWindowS]
/// long. [samples] must be in time order.
int? normalizedPower(List<PowerSample> samples) {
  var sum = 0.0;
  var windows = 0;
  // The rolling window over the current series, as a running total of the
  // last [normalizedPowerWindowS] seconds.
  final ring = List<int>.filled(normalizedPowerWindowS, 0);
  var filled = 0;
  var head = 0;
  var total = 0;

  void reset() {
    filled = 0;
    head = 0;
    total = 0;
  }

  void push(int watts) {
    if (filled == normalizedPowerWindowS) {
      total -= ring[head];
    } else {
      filled++;
    }
    ring[head] = watts;
    total += watts;
    head = (head + 1) % normalizedPowerWindowS;
    if (filled == normalizedPowerWindowS) {
      final mean = total / normalizedPowerWindowS;
      sum += mean * mean * mean * mean;
      windows++;
    }
  }

  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i];
    // The reading covers every second up to the next one, or just its own
    // second when the next is too far off to be the same effort.
    var held = 1;
    if (i + 1 < samples.length) {
      final gap = samples[i + 1].atSeconds - sample.atSeconds;
      if (gap <= 0) continue;
      if (gap <= normalizedPowerGapS) held = gap;
    }
    for (var k = 0; k < held; k++) {
      push(sample.watts);
    }
    if (held == 1 &&
        i + 1 < samples.length &&
        samples[i + 1].atSeconds - sample.atSeconds > normalizedPowerGapS) {
      reset();
    }
  }

  if (windows == 0) return null;
  return math.pow(sum / windows, 0.25).round();
}

/// The zone of [watts] as a share of the [thresholdW]: the last of
/// [powerZoneBoundsPercent] it reaches, counting from zero. Integer
/// arithmetic, so a reading exactly on a boundary lands where the boundary
/// says.
int powerZoneOf(int watts, int thresholdW) {
  final hundredths = watts * 100;
  for (var zone = powerZoneCount - 1; zone > 0; zone--) {
    if (hundredths >= powerZoneBoundsPercent[zone] * thresholdW) return zone;
  }
  return 0;
}
