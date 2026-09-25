import 'dart:math' as math;
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart' show RouteSource;
import 'package:velorki/core/geo/track_surface.dart' show keepAllTags;
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/application/route_geometry.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/off_route_guidance.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/follow_choice.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../support/units.dart';
import '../../recording/support/fakes.dart';

/// Replaying rides through the real navigation controller.
///
/// A ride is a timed run of fixes. Each one goes through the recorder's
/// snapshot stream into [NavigationController], exactly as a phone's would,
/// with the real off-route machine deciding and a real router — the Dart
/// BRouter over a tile on disk — answering every way back and re-plan. What
/// the controller did is written down fix by fix in a [ReplayLog], for the
/// scenarios to hold to account.

/// One fix of a replayed ride.
class ReplayFix {
  /// Creates a fix.
  const ReplayFix(this.pos, this.time, {this.accuracyM = 6});

  /// Where the phone said the rider was.
  final LatLng pos;

  /// When.
  final DateTime time;

  /// How sure it said it was, in metres.
  final double? accuracyM;
}

/// A routing request the controller made during a replay, with its answer.
class ReplayRouting {
  /// Creates the entry.
  const ReplayRouting(this.at, this.query, this.result);

  /// When, by the ride's clock.
  final DateTime at;

  /// What was asked.
  final RouteQuery query;

  /// What came back, or `null` for no route.
  final RouteResult? result;
}

/// A route the controller put the rider on during a replay: a way back
/// onto the plan, or the plan itself re-planned.
class ReplayAdopted {
  /// Creates the entry.
  const ReplayAdopted({
    required this.at,
    required this.replacesPlan,
    required this.rejoinAlongM,
    required this.riderAlongM,
    required this.result,
  });

  /// When, by the ride's clock.
  final DateTime at;

  /// Whether the whole ride was re-planned.
  final bool replacesPlan;

  /// Where a way back meets the plan, in metres along it.
  final double rejoinAlongM;

  /// Where the rider was along the plan when it was adopted, by projection.
  final double riderAlongM;

  /// The router's answer it was made from.
  final RouteResult? result;
}

/// What the controller did over a replayed ride.
class ReplayLog {
  /// Every routing request.
  final List<ReplayRouting> routings = <ReplayRouting>[];

  /// Every route adopted.
  final List<ReplayAdopted> adopted = <ReplayAdopted>[];

  /// The off-route state after each fix.
  final List<(DateTime, OffRouteState)> states = <(DateTime, OffRouteState)>[];

  /// The ride's length along the plan, in metres.
  double planLengthM = 0;

  /// Ways back and re-plans adopted.
  int get reroutes => adopted.length;

  /// How often the state went from on the route to off it or back.
  int get flips {
    var flips = 0;
    for (var i = 1; i < states.length; i++) {
      final was = states[i - 1].$2 == OffRouteState.onRoute;
      final now = states[i].$2 == OffRouteState.onRoute;
      if (was != now) flips++;
    }
    return flips;
  }

  /// The most flips inside any one minute of the ride.
  int get flipsPerMinuteMax {
    final at = <DateTime>[];
    for (var i = 1; i < states.length; i++) {
      final was = states[i - 1].$2 == OffRouteState.onRoute;
      final now = states[i].$2 == OffRouteState.onRoute;
      if (was != now) at.add(states[i].$1);
    }
    var most = 0;
    for (var i = 0; i < at.length; i++) {
      var n = 0;
      for (var j = i; j < at.length; j++) {
        if (at[j].difference(at[i]) < const Duration(minutes: 1)) n++;
      }
      most = math.max(most, n);
    }
    return most;
  }

  /// Whether the state was ever anything but on the route.
  bool get everOff => states.any((s) => s.$2 != OffRouteState.onRoute);

  /// How long the longest run of fixes off the route lasted.
  Duration get longestOff {
    var longest = Duration.zero;
    DateTime? since;
    for (final (at, state) in states) {
      if (state == OffRouteState.onRoute) {
        if (since != null) {
          final run = at.difference(since);
          if (run > longest) longest = run;
        }
        since = null;
      } else {
        since ??= at;
      }
    }
    return longest;
  }

  @override
  String toString() {
    final lines = <String>[
      'plan ${planLengthM.round()} m, ${routings.length} routing requests, '
          '$reroutes adopted, $flips flips',
      for (final a in adopted)
        '  ${_clock(a.at)} ${a.replacesPlan ? 'RE-PLAN' : 'rejoin at ${a.rejoinAlongM.round()} m'}'
            ' with the rider at ${a.riderAlongM.round()} m',
      for (var i = 1; i < states.length; i++)
        if (states[i].$2 != states[i - 1].$2)
          '  ${_clock(states[i].$1)} ${states[i].$2.name}',
    ];
    return lines.join('\n');
  }
}

String _clock(DateTime at) => at.toIso8601String().substring(11, 19);

/// Records every request the controller sends, asking for every tag so the
/// scenarios can check the answers.
class _RecordingRouter implements RoutingBackend {
  _RecordingRouter(this.inner, this.log, this.clock);

  final RoutingBackend inner;
  final ReplayLog log;
  final DateTime Function() clock;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    final asked = q.copyWith(profileParams: keepAllTags);
    try {
      final result = await inner.route(asked, cancel: cancel);
      log.routings.add(ReplayRouting(clock(), asked, result));
      return result;
    } on RoutingException {
      log.routings.add(ReplayRouting(clock(), asked, null));
      rethrow;
    }
  }
}

class _NoPlan extends PlannerController {
  @override
  PlannerState build() => const PlannerState();
}

/// Rides [fixes] along the saved route [line] (planned through
/// [waypoints], with [options]) through the navigation controller, routing
/// with [backend], and says what the controller did.
Future<ReplayLog> replayRide({
  required List<LatLng> line,
  required List<LatLng> waypoints,
  required List<ReplayFix> fixes,
  required RoutingBackend backend,
  RoutingOptions options = const RoutingOptions(),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final service = FakeRecordingService();
  final log = ReplayLog();
  var now = fixes.first.time;
  final router = _RecordingRouter(backend, log, () => now);
  final saved = SavedRoute(
    id: 'replay',
    name: 'Replay',
    source: RouteSource.planned,
    profile: options.profile,
    createdAt: now,
    updatedAt: now,
    distanceM: 0,
    ascentM: 0,
    descentM: 0,
    bounds: BoundingBox.fromPoints(line),
    geometryBlob: PackedTrack.encode(<TrackPoint>[
      for (final p in line) TrackPoint(p),
    ]),
    waypoints: <Waypoint>[for (final w in waypoints) Waypoint(pos: w)],
    options: options,
  );
  final container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      metricUnits,
      recordingServiceProvider.overrideWithValue(service),
      turnSpeakerProvider.overrideWithValue(FakeTurnSpeaker()),
      navigationLocalizationsProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
      routingBackendProvider.overrideWithValue(router),
      navigationClockProvider.overrideWithValue(() => now),
      plannerControllerProvider.overrideWith(_NoPlan.new),
      savedRouteProvider('replay')
          .overrideWith((ref) => Stream<SavedRoute?>.value(saved)),
    ],
  );
  try {
    container.listen(navigationControllerProvider, (_, _) {});
    container
        .read(recordingControllerProvider.notifier)
        .choose(const FollowSaved('replay'));
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // The plan the rider is held to: the saved route, until a re-plan
    // takes its place.
    var held = line;
    var cumulative = cumulativeDistances(line);
    log.planLengthM = cumulative.isEmpty ? 0 : cumulative.last;
    GuidedRoute? lastDetour;
    var previous = fixes.first;
    for (var i = 0; i < fixes.length; i++) {
      final fix = fixes[i];
      now = fix.time;
      final moved = haversineMeters(previous.pos, fix.pos);
      final seconds = fix.time.difference(previous.time).inMilliseconds / 1000;
      final speed = seconds > 0 ? moved / seconds : 0.0;
      // The phone's course: the direction of travel since the last fix
      // that moved.
      final heading = moved > 3 ? bearingDegrees(previous.pos, fix.pos) : null;
      if (moved > 3) previous = fix;
      service.emit(
        RecordingSnapshot(
          rideId: 'replay',
          status: RecordingStatus.active,
          startedAt: fixes.first.time,
          autoPaused: false,
          distanceM: 0,
          elapsed: fix.time.difference(fixes.first.time),
          moving: fix.time.difference(fixes.first.time),
          speedMps: speed,
          avgSpeedMps: speed,
          ascentM: 0,
          descentM: 0,
          lastPosition: fix.pos,
          headingDeg: heading,
          accuracyM: fix.accuracyM,
          pointCount: i + 1,
          newPoints: const <LatLng>[],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      // Whatever the fix asked the router for is answered before the next
      // fix: on the phone that takes a fraction of a second.
      for (var wait = 0; wait < 1200; wait++) {
        if (!(container.read(navigationControllerProvider)?.rerouting ??
            false)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final progress = container.read(navigationControllerProvider);
      log.states.add((
        fix.time,
        progress?.offRouteState ?? OffRouteState.onRoute,
      ));
      final detour = container.read(detourRouteProvider);
      if (detour != null && !identical(detour, lastDetour)) {
        final drawn = detour.replacesPlan ? detour.line : detour.branch;
        RouteResult? made;
        for (final r in log.routings.reversed) {
          final positions = r.result?.positions;
          if (positions != null &&
              positions.length == drawn.length &&
              positions.first == drawn.first) {
            made = r.result;
            break;
          }
        }
        log.adopted.add(
          ReplayAdopted(
            at: fix.time,
            replacesPlan: detour.replacesPlan,
            rejoinAlongM: detour.rejoinAlongM,
            riderAlongM: projectOnLine(
              held,
              fix.pos,
              cumulative: cumulative,
            ).alongM,
            result: made,
          ),
        );
        if (detour.replacesPlan) {
          held = detour.line;
          cumulative = cumulativeDistances(held);
        }
      }
      lastDetour = detour;
    }
  } finally {
    container.dispose();
    await service.dispose();
  }
  return log;
}

/// Builds rides over real streets for the scenarios.
class RideMaker {
  /// Creates the maker over [backend], riding at [speedMps], a fix a second
  /// from [start].
  RideMaker(this.backend, {this.speedMps = 5, DateTime? start})
    : start = start ?? DateTime.utc(2026, 6, 1, 12);

  /// The router the streets come from.
  final RoutingBackend backend;

  /// How fast the rider goes.
  final double speedMps;

  /// When the ride starts.
  final DateTime start;

  /// The route through [points] with the default bike.
  Future<RouteResult> route(List<LatLng> points, {int alternative = 0}) =>
      backend.route(
        RouteQuery(
          points: points,
          alternativeIdx: alternative,
          profileParams: keepAllTags,
        ),
      );

  /// The ride along [path], a fix a second. [noise] gives each fix its
  /// error in metres and the accuracy the phone reports; without it the
  /// fixes are within four metres and reported at six.
  List<ReplayFix> ride(
    List<LatLng> path, {
    (double, double) Function(int fix, math.Random random)? noise,
    int seed = 1,
  }) {
    final random = math.Random(seed);
    final cumulative = cumulativeDistances(path);
    final fixes = <ReplayFix>[];
    var i = 0;
    for (var m = 0.0; m <= cumulative.last; m += speedMps, i++) {
      final (error, reported) =
          noise?.call(i, random) ?? (random.nextDouble() * 4, 6.0);
      fixes.add(
        ReplayFix(
          destinationPoint(
            pointAt(path, cumulative, m),
            random.nextDouble() * 360,
            error,
          ),
          start.add(Duration(seconds: i)),
          accuracyM: reported,
        ),
      );
    }
    return fixes;
  }

  /// [plan] up to [fromM] metres along, then a way through a point [asideM]
  /// metres to its side (right when positive) halfway to [toM], back onto
  /// the plan at [toM], and the rest of the plan.
  ///
  /// `null` when the streets make that no detour at all: a way round that
  /// runs back along the plan, never gets off it, or is more than three
  /// times the stretch it replaces. Hills and one-ways do that; the caller
  /// tries another stretch.
  Future<List<LatLng>?> detour(
    List<LatLng> plan,
    double fromM,
    double toM,
    double asideM,
  ) async {
    final cumulative = cumulativeDistances(plan);
    final mid = (fromM + toM) / 2;
    final side = destinationPoint(
      pointAt(plan, cumulative, mid),
      headingAt(plan, cumulative, mid) + 90,
      asideM,
    );
    final around = (await route(<LatLng>[
      pointAt(plan, cumulative, fromM),
      side,
      pointAt(plan, cumulative, toM),
    ])).positions;
    if (polylineLengthMeters(around) > 3 * (toM - fromM)) return null;
    var furthest = 0.0;
    var along = fromM;
    for (final p in around) {
      final on = projectOnLine(plan, p, cumulative: cumulative);
      furthest = math.max(furthest, on.distanceM);
      if (on.distanceM < 30 && on.alongM < along - 50) return null;
      if (on.distanceM < 30) along = math.max(along, on.alongM);
    }
    if (furthest < asideM.abs() * 0.5) return null;
    return <LatLng>[
      for (var i = 0; i < plan.length; i++)
        if (cumulative[i] < fromM) plan[i],
      ...around,
      for (var i = 0; i < plan.length; i++)
        if (cumulative[i] > toM) plan[i],
    ];
  }

  /// The first [detour] of [lengthM] metres, [asideM] to either side, that
  /// the streets allow, looked for from a third of the way along [plan] on.
  Future<List<LatLng>> anyDetour(
    List<LatLng> plan,
    double lengthM,
    double asideM,
  ) async {
    final total = cumulativeDistances(plan).last;
    for (var f = 0.3; f + lengthM / total < 0.95; f += 0.05) {
      for (final side in <double>[asideM, -asideM]) {
        final path = await detour(plan, total * f, total * f + lengthM, side);
        if (path != null) return path;
      }
    }
    throw StateError('no $lengthM m detour $asideM m aside on this plan');
  }

  /// A way from [plan]'s start to its end kept [asideM] metres to one side
  /// of it throughout: the next street over, all the way.
  Future<List<LatLng>> beside(List<LatLng> plan, double asideM) async {
    final cumulative = cumulativeDistances(plan);
    final total = cumulative.last;
    final shifted = <LatLng>[
      for (final f in const <double>[0.15, 0.35, 0.55, 0.75])
        destinationPoint(
          pointAt(plan, cumulative, total * f),
          headingAt(plan, cumulative, total * f) + 90,
          asideM,
        ),
    ];
    return (await route(<LatLng>[plan.first, ...shifted, plan.last])).positions;
  }
}

/// The point [metres] along [line].
LatLng pointAt(List<LatLng> line, List<double> cumulative, double metres) {
  for (var i = 1; i < line.length; i++) {
    if (cumulative[i] >= metres) {
      final span = cumulative[i] - cumulative[i - 1];
      final t = span <= 0 ? 0.0 : (metres - cumulative[i - 1]) / span;
      return LatLng(
        line[i - 1].lat + (line[i].lat - line[i - 1].lat) * t,
        line[i - 1].lon + (line[i].lon - line[i - 1].lon) * t,
      );
    }
  }
  return line.last;
}

/// Which way [line] runs at [metres] along it.
double headingAt(List<LatLng> line, List<double> cumulative, double metres) =>
    bearingDegrees(
      pointAt(line, cumulative, math.max(0, metres - 10)),
      pointAt(line, cumulative, math.min(cumulative.last, metres + 10)),
    );
