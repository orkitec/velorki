import '../data/health_gateway.dart';

/// One workout [FakeHealthGateway] was asked to write.
class RecordedWorkout {
  /// Creates a record.
  const RecordedWorkout({
    required this.start,
    required this.end,
    required this.distanceM,
    this.avgHeartRateBpm,
  });

  /// When the ride began.
  final DateTime start;

  /// When it ended.
  final DateTime end;

  /// How far it went, in metres.
  final double distanceM;

  /// The mean heart rate handed over, `null` when the ride had none.
  final double? avgHeartRateBpm;

  @override
  String toString() =>
      'RecordedWorkout($start → $end, ${distanceM.toStringAsFixed(1)} m, '
      'hr: $avgHeartRateBpm)';
}

/// A [HealthGateway] with scripted samples that writes down what it was asked
/// to do.
///
/// Lives in `lib/` rather than `test/` so the widget tests and the integration
/// tests can both override `healthGatewayProvider` with it — the same reason
/// `FakeTurnSpeaker` does.
class FakeHealthGateway implements HealthGateway {
  /// Creates a fake that holds [samples] and answers [available].
  FakeHealthGateway({
    List<HeartRateSample> samples = const <HeartRateSample>[],
    this.available = true,
    this.grants = true,
    this.granted = false,
    this.writeSucceeds = true,
  }) : samples = <HeartRateSample>[...samples];

  /// The samples [heartRate] answers from; a test may add to this at any time.
  final List<HeartRateSample> samples;

  /// What [isAvailable] answers.
  bool available;

  /// What [requestAuthorization] answers — `false` is an OS that refused.
  bool grants;

  /// What [hasAuthorization] answers.
  bool granted;

  /// Whether [writeCyclingWorkout] claims to have written the workout.
  bool writeSucceeds;

  /// Every window [heartRate] was asked for, in order.
  final List<({DateTime from, DateTime to})> queries =
      <({DateTime from, DateTime to})>[];

  /// Called at the start of every [heartRate] query with the window asked for,
  /// before [samples] is read.
  ///
  /// A store that keeps being written to while a ride runs is what the live
  /// source actually polls, and a fixed list cannot be that; a test that wants
  /// one appends a fresh sample here.
  void Function(DateTime from, DateTime to)? onQuery;

  /// Every authorization request, in order, with the `write` it asked for.
  final List<bool> authorizations = <bool>[];

  /// Every workout [writeCyclingWorkout] was asked to write, in order.
  final List<RecordedWorkout> workouts = <RecordedWorkout>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> requestAuthorization({required bool write}) async {
    authorizations.add(write);
    if (grants) granted = true;
    return grants;
  }

  @override
  Future<bool> hasAuthorization({required bool write}) async => granted;

  @override
  Future<List<HeartRateSample>> heartRate(DateTime from, DateTime to) async {
    queries.add((from: from, to: to));
    onQuery?.call(from, to);
    return <HeartRateSample>[
      for (final sample in samples)
        if (!sample.at.isBefore(from) && !sample.at.isAfter(to)) sample,
    ]..sort((a, b) => a.at.compareTo(b.at));
  }

  @override
  Future<bool> writeCyclingWorkout({
    required DateTime start,
    required DateTime end,
    required double distanceM,
    double? avgHeartRateBpm,
  }) async {
    workouts.add(
      RecordedWorkout(
        start: start,
        end: end,
        distanceM: distanceM,
        avgHeartRateBpm: avgHeartRateBpm,
      ),
    );
    return writeSucceeds;
  }
}
