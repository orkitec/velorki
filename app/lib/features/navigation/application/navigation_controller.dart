import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/data/routing_backend_provider.dart';
import '../../planner/domain/routing_options.dart';
import '../../recording/application/recording_controller.dart';
import '../../recording/domain/recording_snapshot.dart';
import '../data/navigation_settings.dart';
import '../data/turn_speaker.dart';
import '../domain/navigation_progress.dart';
import '../domain/off_route_guidance.dart';
import '../presentation/turn_phrases.dart';
import '../../settings/data/language_controller.dart';
import '../../settings/data/units.dart';
import 'off_route_machine.dart';
import 'off_route_thresholds.dart';
import 'route_geometry.dart';
import 'turn_announcer.dart';
import 'turn_navigator.dart';

part 'navigation_controller.g.dart';

/// How long after a routing attempt the next one may go out.
const Duration rerouteGap = Duration(seconds: 20);

/// The same after a failed attempt: longer, so a router that is down or out
/// of reach is asked again at a sensible pace.
const Duration rerouteRetryGap = Duration(seconds: 30);

/// How long a routing request is given before it is abandoned.
const Duration rerouteTimeout = Duration(seconds: 20);

/// The route a ride is being guided along, plus a key that says when it is a
/// different route from the one before.
@immutable
class GuidedRoute {
  /// Creates the route.
  const GuidedRoute({
    required this.key,
    required this.line,
    required this.turns,
    this.waypoints = const <LatLng>[],
    this.options = const RoutingOptions(),
    this.branch = const <LatLng>[],
    this.rejoinAlongM = 0,
    this.replacesPlan = false,
  });

  /// Identity of the route: the saved route's id, or, for a plan that was
  /// never saved, the shape of its geometry.
  final String key;

  /// The geometry the rider is matched against.
  ///
  /// For a rejoin this is the whole way to the end of the ride: the way back
  /// onto the plan followed by the rest of the plan, so the navigator and the
  /// announcer see one continuous route rather than two.
  final List<LatLng> line;

  /// The turn instructions anchored to [line].
  final List<TurnHint> turns;

  /// The points the route was planned through, start first.
  ///
  /// Empty for a route that carries none — an imported GPX track, say — in
  /// which case a re-route heads straight for the end of [line].
  final List<LatLng> waypoints;

  /// The profile and alternative the route was computed with, so a re-route
  /// takes the same kind of roads.
  final RoutingOptions options;

  /// The part of [line] that is new, for a rejoin: the way from where the
  /// rider strayed to back onto the plan. Empty for a plain route.
  ///
  /// The map draws this on its own so the plan can stay where it is: a rider
  /// has to see the branch and the road it leaves to know what is being asked
  /// of them.
  final List<LatLng> branch;

  /// How far along the plan a rejoin meets it again, in metres.
  final double rejoinAlongM;

  /// Whether this route replaces the plan rather than rejoining it: the whole
  /// ride re-planned to its destination from where the rider stood.
  final bool replacesPlan;
}

/// The route the record screen draws and the navigator follows: the saved
/// route the rider chose, or the plan on the Plan tab when they chose none.
///
/// A provider of its own because the saved route is a family whose argument
/// changes while the app runs; this one is allowed to rebuild, so the
/// navigation controller below never has to.
@Riverpod(keepAlive: true)
GuidedRoute? guidedRoute(Ref ref) {
  final followed = ref.watch(
    recordingControllerProvider.select((s) => s.followedRouteId),
  );
  if (followed != null) {
    final route = ref.watch(savedRouteProvider(followed)).value;
    if (route == null) return null;
    final line = route.geometry.map((p) => p.pos).toList(growable: false);
    return GuidedRoute(
      key: 'saved:${route.id}',
      line: line,
      turns: route.turns,
      waypoints: route.waypoints.map((w) => w.pos).toList(growable: false),
      options: route.options,
    );
  }
  final result = ref.watch(plannerControllerProvider.select((s) => s.result));
  final planned = ref.watch(
    plannerControllerProvider.select((s) => s.waypoints),
  );
  final options = ref.watch(plannerControllerProvider.select((s) => s.options));
  final line = result?.positions ?? const <LatLng>[];
  if (result == null || line.isEmpty) return null;
  // A plan has no id, so its shape stands in for one: a recomputed plan
  // always changes the point count or one of the ends.
  return GuidedRoute(
    key: 'plan:${line.length}:${line.first}:${line.last}',
    line: line,
    turns: result.turns,
    waypoints: planned.map((w) => w.pos).toList(growable: false),
    options: options,
  );
}

/// The way back onto the route the controller worked out after the rider left
/// it, or `null` while the plan itself is being navigated.
///
/// Two different things live here. A rejoin carries a [GuidedRoute.branch] and
/// leaves the plan on the map beside it; a whole new route to the destination
/// carries none and takes the plan's place. Only [NavigationController] writes
/// this; everyone else reads it.
@Riverpod(keepAlive: true)
class DetourRoute extends _$DetourRoute {
  @override
  GuidedRoute? build() => null;

  /// Puts [route] in the navigator's hands, or takes the detour away again.
  void replace(GuidedRoute? route) => state = route;
}

/// Whether the spoken turns are silenced for the rest of this ride.
///
/// Not a setting: it is the button on the banner for a rider who wants quiet
/// right now, so it lasts as long as the ride does and no longer. The cues are
/// still worked out while it is on, so the banner keeps counting the turns
/// down and the voice picks up again where it left off.
@Riverpod(keepAlive: true)
class VoiceMutedForRide extends _$VoiceMutedForRide {
  @override
  bool build() => false;

  /// Silences the voice, or gives it back.
  void toggle() => state = !state;

  /// Gives the voice back, which is where every ride starts.
  void reset() => state = false;
}

/// The route navigation is actually running on: the detour while one is up,
/// the plan the rider chose otherwise.
@Riverpod(keepAlive: true)
GuidedRoute? activeGuidedRoute(Ref ref) =>
    ref.watch(detourRouteProvider) ?? ref.watch(guidedRouteProvider);

/// The clock the re-route back-off is measured against.
///
/// A provider so tests can wind it forward without waiting; nothing else in
/// navigation cares what time it is.
@Riverpod(keepAlive: true)
DateTime Function() navigationClock(Ref ref) => DateTime.now;

/// The localisations the spoken cues are built from.
///
/// The controller has no [BuildContext], so it looks the strings up itself:
/// by the app's own language setting when the rider chose one, else by the
/// platform locale, the same rule the screens follow. The voice follows the
/// same choice (see `cueLocaleTag`), so text and voice never part ways. A
/// locale the app has no translation for falls back to English. Tests
/// override this provider to pin the language.
@Riverpod(keepAlive: true)
AppLocalizations navigationLocalizations(Ref ref) {
  final locale =
      ref.watch(appLocaleProvider) ??
      WidgetsBinding.instance.platformDispatcher.locale;
  try {
    return lookupAppLocalizations(locale);
  } catch (_) {
    return lookupAppLocalizations(const Locale('en'));
  }
}

/// Where the rider is on the guided route, or `null` when nothing is guided.
///
/// Everything here is driven by listeners rather than by `ref.watch`: the
/// controller writes its own state on every position fix, and watching the
/// recorder would rebuild it in a loop. It is kept alive for the whole session
/// so a ride keeps its navigator while the rider is on another tab; `HomeShell`
/// reads it once so that session actually starts.
///
/// It also repairs a ride that has gone astray, in the order a rider would
/// want it repaired: [OffRouteMachine] decides, and this acts. First the plan
/// itself points them back at the nearest bit of it still ahead of them, with
/// no routing at all; only if they are still off it half a minute later is a
/// way back computed and hung off the plan as a branch; and only a rider who
/// is kilometres away for minutes, or who asks for it, has the whole ride
/// re-planned to its destination.
@Riverpod(keepAlive: true)
class NavigationController extends _$NavigationController {
  TurnNavigator? _navigator;
  TurnAnnouncer? _announcer;
  OffRouteMachine? _machine;

  /// Whether the voice choice has reached the speaker, and which one.
  bool _voiceApplied = false;
  String? _appliedVoiceId;

  /// Identity of the route the navigator was built for: the rejoin while one
  /// is up, the plan otherwise.
  String? _routeKey;

  /// Identity of the plan itself, so a different route starts from scratch.
  String? _planKey;

  /// Identity of the plan the off-route machine was built for.
  String? _machineKey;

  /// Distance from the start of the plan to each of its points, kept because
  /// every fix is projected onto the plan.
  List<double> _planCumulative = const <double>[];

  /// The ride the current guidance belongs to, for the same reason.
  String? _rideId;

  /// The snapshot already fed to the navigator, so a settings change does not
  /// run the same fix through the announcer twice.
  RecordingSnapshot? _fedSnapshot;

  /// The last progress, mirrored here because `state` cannot be read while
  /// the notifier is building.
  NavigationProgress? _progress;

  /// Whether guidance was running on the previous pass, so the speaker is
  /// silenced exactly once when it stops.
  bool _guiding = false;

  /// Whether the speaker is holding the phone's audio right now; see
  /// [_holdAudio].
  bool _audioHeld = false;

  /// Whether a ride was running on the previous pass, so the ride-only mute
  /// is lifted exactly once when one starts or ends.
  bool _recording = false;

  /// How far along the plan the rider was when last matched to it. A rejoin
  /// is aimed from here on, so the corners already ridden are left alone.
  double _planAlongM = 0;

  /// Where the ride stands in relation to the plan, and the way back.
  OffRouteState _offRouteState = OffRouteState.onRoute;
  OffRouteGuidance? _guidance;

  /// Whether a routing request is out right now.
  bool _rerouting = false;

  /// Cancels the request in flight.
  CancelToken? _cancel;

  /// Counts the requests, so an answer to one that was given up on is
  /// dropped rather than followed.
  int _generation = 0;

  /// When the last request went out, and how long the next one has to wait.
  DateTime? _lastAttemptAt;
  Duration _gap = rerouteGap;

  /// How many detours this ride has had, so two of the same shape are still
  /// two different routes as far as the navigator is concerned.
  int _detours = 0;

  /// Whether the notifier is being created right now.
  bool _building = false;

  @override
  NavigationProgress? build() {
    ref.listen(recordingControllerProvider, (previous, next) => _refresh());
    ref.listen(navigationSettingsProvider, (previous, next) => _refresh());
    ref.listen(guidedRouteProvider, (previous, next) => _refresh());
    // The mute is the one switch that is not read on every pass anyway, and
    // it has to reach the speaker the moment it is flipped: it is what gives
    // the phone's audio back mid-ride.
    ref.listen(voiceMutedForRideProvider, (previous, next) => _refresh());
    ref.onDispose(_forget);
    _building = true;
    final initial = _compute();
    _building = false;
    return initial;
  }

  void _refresh() => state = _compute();

  /// Works out the progress for whatever the recorder, the settings and the
  /// route say right now.
  NavigationProgress? _compute() {
    final recording = ref.read(recordingControllerProvider);
    // The mute belongs to one ride: starting or ending a ride gives the
    // voice back, whether or not that ride was being guided.
    if (recording.isRecording != _recording) {
      _recording = recording.isRecording;
      _unmute();
    }
    final settings = ref.read(navigationSettingsProvider);
    final chosen = ref.read(guidedRouteProvider);
    final guided =
        recording.isRecording &&
        settings.turns &&
        (chosen?.line.length ?? 0) >= 2;
    if (!guided || chosen == null) {
      _stop();
      return null;
    }

    final snapshot = recording.snapshot;
    final position = snapshot?.lastPosition;

    // Another route, or another ride: anything worked out for the old one
    // belongs to neither.
    final rideId = snapshot?.rideId;
    if (chosen.key != _planKey || (rideId != null && rideId != _rideId)) {
      _planKey = chosen.key;
      if (rideId != null) _rideId = rideId;
      _planAlongM = 0;
      _detours = 0;
      _offRouteState = OffRouteState.onRoute;
      _guidance = null;
      _cancelRouting();
      _setDetour(null);
    }

    // The plan is the route the rider chose, unless the ride was re-planned
    // to its destination, in which case that new route is the plan.
    final held = ref.read(detourRouteProvider);
    final plan = held != null && held.replacesPlan ? held : chosen;
    final detour = held != null && !held.replacesPlan ? held : null;
    if (plan.key != _machineKey) {
      _machineKey = plan.key;
      _machine = OffRouteMachine(line: plan.line);
      _planCumulative = cumulativeDistances(plan.line);
    }

    _ensureNavigator(detour ?? plan, plan);
    _guiding = true;
    _holdAudio(settings.voice && !ref.read(voiceMutedForRideProvider));

    // Nothing new to match: keep showing what the last fix said.
    if (snapshot == null ||
        position == null ||
        identical(snapshot, _fedSnapshot)) {
      return _decorate(_progress);
    }

    final now = ref.read(navigationClockProvider)();
    // Where the ride stands is worked out before the fix is matched, because
    // the answer decides what it is matched against: a rider who has just
    // found the plan again belongs on the plan from this fix, not the next.
    _decide(plan, detour, snapshot, position, now, settings.reroute);
    final stored = ref.read(detourRouteProvider);
    _ensureNavigator(
      stored != null && !stored.replacesPlan ? stored : plan,
      plan,
    );
    _fedSnapshot = snapshot;

    final progress = _navigator!.update(
      position,
      now: now,
      accuracyM: snapshot.accuracyM,
    );
    _progress = progress;
    final cues = _announcer!.update(
      progress,
      speedMps: snapshot.speedMps,
      leadSeconds: settings.leadSeconds,
    );
    if (cues.isNotEmpty && settings.voice) _speak(cues);

    return _decorate(progress);
  }

  /// Builds the navigator and the announcer for [route], if they are not the
  /// ones already running.
  void _ensureNavigator(GuidedRoute route, GuidedRoute plan) {
    if (route.key == _routeKey) return;
    _routeKey = route.key;
    _navigator = TurnNavigator(
      line: route.line,
      turns: route.turns,
      // Handed back to the plan after a rejoin, the rider is already well
      // along it; without this the first fix would be matched near its start.
      resumeAlongM: identical(route, plan) ? _planAlongM : 0,
    );
    _announcer = TurnAnnouncer();
    _fedSnapshot = null;
    _progress = null;
  }

  /// Runs one fix through the off-route machine and does what it asks for.
  void _decide(
    GuidedRoute plan,
    GuidedRoute? detour,
    RecordingSnapshot snapshot,
    LatLng position,
    DateTime now,
    bool rerouteAllowed,
  ) {
    final machine = _machine;
    if (machine == null) return;
    final onPlan = projectOnLine(
      plan.line,
      position,
      cumulative: _planCumulative,
    );
    // Only a fix that is really on the plan moves the rider along it: a
    // rejoin is aimed from the last corner they actually rode. The same gate
    // the machine restores on, so the two never disagree about where the
    // rider stands.
    if (onPlan.distanceM <= snapThresholdM(snapshot.accuracyM)) {
      _planAlongM = onPlan.alongM;
    }

    final decision = machine.update(
      position: position,
      distanceFromRouteM: onPlan.distanceM,
      alongM: _planAlongM,
      speedMps: snapshot.speedMps,
      headingDeg: snapshot.headingDeg,
      now: now,
      rerouteAllowed: rerouteAllowed,
      distanceFromDetourM: detour == null
          ? null
          : projectOnLine(detour.branch, position).distanceM,
      accuracyM: snapshot.accuracyM,
    );
    _offRouteState = decision.state;
    _guidance = decision.guidance;

    // Back on the plan: the branch has done its job, whether or not it ever
    // reached its own rejoin point.
    if (decision.restored && detour != null) {
      _cancelRouting();
      _setDetour(null);
    }
    if (decision.speakGuidance &&
        ref.read(navigationSettingsProvider).voice &&
        decision.guidance != null) {
      _speak(<TurnCue>[
        TurnCue(
          kind: CueKind.backToRoute,
          distanceM: roundedAheadMeters(decision.guidance!.distanceM),
          direction: decision.guidance!.direction,
        ),
      ]);
    }
    if (decision.fullReroute) {
      _startFullReroute(plan, position, now);
    } else if (decision.planDetour) {
      _startRejoin(plan, position, snapshot, now);
    }
  }

  /// Adds the controller's own fields to [progress], which the navigator
  /// knows nothing about.
  NavigationProgress? _decorate(NavigationProgress? progress) =>
      progress?.decorated(
        rerouting: _rerouting,
        offRouteState: _offRouteState,
        guidance: _guidance,
      );

  /// Works out a way back onto the plan now, because the rider asked for one
  /// by tapping the banner.
  ///
  /// Does nothing while the rider has re-routing switched off: then the plan
  /// itself is the only guidance they asked for.
  void requestRejoin() {
    if (!ref.read(navigationSettingsProvider).reroute) return;
    final plan = _currentPlan();
    final snapshot = ref.read(recordingControllerProvider).snapshot;
    final position = snapshot?.lastPosition;
    if (plan == null || snapshot == null || position == null) return;
    if (_offRouteState == OffRouteState.onRoute) return;
    _lastAttemptAt = null;
    _startRejoin(plan, position, snapshot, ref.read(navigationClockProvider)());
    _refresh();
  }

  /// Plans a whole new route from where the rider stands to the end of the
  /// ride, because they asked for one. Always allowed: it is the rider's own
  /// decision, not something the app worked out for them.
  void requestFullReroute() {
    final plan = _currentPlan();
    final position = ref
        .read(recordingControllerProvider)
        .snapshot
        ?.lastPosition;
    if (plan == null || position == null) return;
    _lastAttemptAt = null;
    _startFullReroute(plan, position, ref.read(navigationClockProvider)());
    _refresh();
  }

  /// The route the ride is being held to: the re-planned one when there is
  /// one, the chosen one otherwise.
  GuidedRoute? _currentPlan() {
    final stored = ref.read(detourRouteProvider);
    if (stored != null && stored.replacesPlan) return stored;
    return ref.read(guidedRouteProvider);
  }

  /// Whether a routing request may go out now: none in flight, a backend to
  /// ask, and the last attempt long enough ago that the next one is not
  /// simply the same question again.
  RoutingBackend? _backendFor(DateTime now) {
    if (_rerouting) return null;
    final last = _lastAttemptAt;
    if (last != null && now.difference(last) < _gap) return null;
    return ref.read(routingBackendProvider);
  }

  /// Asks the router for a way from where the rider stands back onto the
  /// plan, trying [rejoinTargetsM] metres further along it.
  ///
  /// The candidates are routed one after another rather than three at a time,
  /// because on the device they share one engine — and because the first one
  /// that works is the answer, so the later ones are usually never asked.
  void _startRejoin(
    GuidedRoute plan,
    LatLng position,
    RecordingSnapshot snapshot,
    DateTime now,
  ) {
    final backend = _backendFor(now);
    if (backend == null) return;
    final targets = rejoinTargets(plan.line, _planCumulative, _planAlongM);
    if (targets.isEmpty) return;

    _lastAttemptAt = now;
    _gap = rerouteGap;
    _rerouting = true;
    final generation = ++_generation;
    final token = CancelToken();
    _cancel = token;
    // BRouter takes no heading, so the only way to say "I am going this way"
    // is to ask for a route through a point that way.
    final via = headingViaPoint(
      position: position,
      headingDeg: snapshot.headingDeg,
      speedMps: snapshot.speedMps,
    );
    unawaited(
      _routeRejoin(backend, plan, position, via, targets, token).then(
        (best) => _rejoined(generation, plan, best),
        onError: (Object error) => _routingFailed(generation, error),
      ),
    );
  }

  /// Routes the candidates in turn and takes the first that is a way back
  /// rather than a loop, or the shortest of them when none is.
  ///
  /// `null` when nothing could be routed at all.
  Future<_Rejoin?> _routeRejoin(
    RoutingBackend backend,
    GuidedRoute plan,
    LatLng position,
    LatLng? via,
    List<RejoinTarget> targets,
    CancelToken token,
  ) async {
    _Rejoin? shortest;
    RoutingException? failure;
    for (final target in targets) {
      if (token.isCancelled) break;
      final query = RouteQuery(
        points: <LatLng>[position, ?via, target.point],
        profile: plan.options.profile.brouterName,
        alternativeIdx: 0,
        timeout: rerouteTimeout,
      );
      try {
        final result = await backend.route(query, cancel: token);
        if (result.positions.length < 2) continue;
        final rejoin = _Rejoin(result: result, target: target);
        // Near enough its own beeline to be a road rather than a way round
        // something: the nearest of those is the way back, and the candidates
        // further on need not be asked for at all.
        final beeline = haversineMeters(position, target.point);
        if (result.lengthM <= beeline * rejoinDetourFactor) return rejoin;
        if (shortest == null || result.lengthM < shortest.result.lengthM) {
          shortest = rejoin;
        }
      } on RoutingException catch (error) {
        // One target out of reach is normal — a one-way street, a river —
        // and only matters when every one of them is.
        failure = error;
      }
    }
    if (shortest == null && failure != null) throw failure;
    return shortest;
  }

  /// Hangs a rejoin off the plan: from here the rider is guided along the way
  /// back and straight on into the rest of the plan.
  void _rejoined(int generation, GuidedRoute plan, _Rejoin? best) {
    if (generation != _generation) return;
    _rerouting = false;
    _cancel = null;
    if (best == null) {
      _refresh();
      return;
    }
    _detours++;
    _setDetour(_stitch(plan, best));
    _machine?.detourStarted(ref.read(navigationClockProvider)());
    _offRouteState = OffRouteState.detour;
    _guidance = null;
    _refresh();
  }

  /// The way back followed by the rest of the plan, as one route.
  ///
  /// The navigator and the announcer see a single line with a single run of
  /// turns, so the rider is counted down to the corner after the rejoin
  /// exactly as they would have been had they never left.
  GuidedRoute _stitch(GuidedRoute plan, _Rejoin best) {
    final branch = best.result.positions;
    final index = math.min(best.target.index, plan.line.length - 1);
    final tail = plan.line.sublist(math.min(index + 1, plan.line.length));
    final shift = branch.length - index - 1;
    final turns = <TurnHint>[
      // The way back ends where the plan picks up again, so its own "arrive"
      // is not an arrival at all.
      for (final hint in best.result.turns)
        if (hint.kind != TurnKind.end) hint,
      for (final hint in plan.turns)
        if (hint.pointIndex > index)
          TurnHint(
            pointIndex: hint.pointIndex + shift,
            kind: hint.kind,
            exitNumber: hint.exitNumber,
            distanceToNextM: hint.distanceToNextM,
            angleDeg: hint.angleDeg,
          ),
    ];
    return GuidedRoute(
      key: 'detour:$_detours:${branch.length}',
      line: <LatLng>[...branch, ...tail],
      turns: turns,
      options: plan.options,
      branch: branch,
      rejoinAlongM: best.target.alongM,
    );
  }

  /// Asks the router for a whole new route from where the rider stands to the
  /// end of the ride. The answer takes the plan's place.
  void _startFullReroute(GuidedRoute plan, LatLng position, DateTime now) {
    final backend = _backendFor(now);
    if (backend == null) return;
    _lastAttemptAt = now;
    _gap = rerouteGap;
    _rerouting = true;
    final generation = ++_generation;
    final token = CancelToken();
    _cancel = token;
    final query = RouteQuery(
      points: <LatLng>[
        position,
        ...remainingWaypoints(plan.line, plan.waypoints, _planAlongM),
      ],
      profile: plan.options.profile.brouterName,
      alternativeIdx: 0,
      timeout: rerouteTimeout,
    );
    unawaited(
      backend
          .route(query, cancel: token)
          .then(
            (result) => _replanned(generation, plan, result),
            onError: (Object error) => _routingFailed(generation, error),
          ),
    );
  }

  /// Takes a fresh route on as the plan itself.
  void _replanned(int generation, GuidedRoute plan, RouteResult result) {
    if (generation != _generation) return;
    _rerouting = false;
    _cancel = null;
    final line = result.positions;
    // A one-point answer is no route; the next fix asks again.
    if (line.length < 2) {
      _refresh();
      return;
    }
    _detours++;
    _planAlongM = 0;
    _offRouteState = OffRouteState.onRoute;
    _guidance = null;
    _setDetour(
      GuidedRoute(
        key: 'reroute:$_detours:${line.length}',
        line: line,
        turns: result.turns,
        waypoints: plan.waypoints,
        options: plan.options,
        replacesPlan: true,
      ),
    );
    if (ref.read(navigationSettingsProvider).voice) {
      _speak(const <TurnCue>[TurnCue(kind: CueKind.rerouted)]);
    }
    _refresh();
  }

  /// A failed attempt changes nothing the rider can see: they are still off
  /// route, and the next attempt waits a little longer.
  void _routingFailed(int generation, Object error) {
    if (generation != _generation) return;
    _rerouting = false;
    _cancel = null;
    debugPrint('Navigation: re-route failed: $error');
    _lastAttemptAt = ref.read(navigationClockProvider)();
    _gap = rerouteRetryGap;
    _refresh();
  }

  /// Writes the detour through its own provider, so the record screen can
  /// draw it. Silent when nothing changed, which is the usual case.
  void _setDetour(GuidedRoute? route) {
    // A provider may not change another one while it is being created, and
    // there is nothing to change anyway: a controller that has just been
    // built has no detour behind it.
    if (_building) return;
    if (ref.read(detourRouteProvider) == route) return;
    ref.read(detourRouteProvider.notifier).replace(route);
  }

  /// Lifts the ride-only mute. Silent when nothing is muted, which is the
  /// usual case.
  void _unmute() {
    // A provider may not change another one while it is being created, and a
    // controller that has just been built has no muted ride behind it.
    if (_building) return;
    if (!ref.read(voiceMutedForRideProvider)) return;
    ref.read(voiceMutedForRideProvider.notifier).reset();
  }

  /// Gives up on the request in flight and forgets the back-off.
  void _cancelRouting() {
    _cancel?.cancel('the route changed');
    _cancel = null;
    _generation++;
    _rerouting = false;
    _lastAttemptAt = null;
    _gap = rerouteGap;
  }

  void _speak(List<TurnCue> cues) {
    // Muted for this ride: the cues were still worked out, they simply are
    // not said.
    if (ref.read(voiceMutedForRideProvider)) return;
    final l10n = ref.read(navigationLocalizationsProvider);
    final speaker = ref.read(turnSpeakerProvider);
    // The chosen voice is handed to the speaker before the first cue of a
    // session and again whenever the choice changes; the speaker queues it
    // ahead of the cues that follow.
    final voiceId = ref.read(navigationSettingsProvider).voiceId;
    if (!_voiceApplied || voiceId != _appliedVoiceId) {
      _voiceApplied = true;
      _appliedVoiceId = voiceId;
      unawaited(speaker.selectVoice(voiceId));
    }
    for (final cue in cues) {
      final phrase = cuePhrase(cue, l10n, units: ref.read(unitSystemProvider));
      // Only the cue for the corner the rider is at may cut another one off.
      if (phrase.isNotEmpty) {
        unawaited(speaker.speak(phrase, urgent: cue.kind == CueKind.now));
      }
    }
  }

  /// Ends a guided ride: the detour, the navigator and the announcer go, and
  /// anything still queued in the speaker is dropped.
  void _stop() {
    _setDetour(null);
    _forget();
    _holdAudio(false);
    if (!_guiding) return;
    _guiding = false;
    unawaited(ref.read(turnSpeakerProvider).stop());
  }

  /// Claims the phone's audio while the turns are being spoken, and gives it
  /// back as soon as they are not: the voice switched off, the ride muted
  /// from the banner, or the guidance over.
  ///
  /// On iOS that is one audio session held open for the whole stretch rather
  /// than one per cue, which is what a Bluetooth headset needs; see
  /// [TurnSpeaker.beginGuidance]. On Android it costs nothing.
  void _holdAudio(bool wanted) {
    if (wanted == _audioHeld) return;
    _audioHeld = wanted;
    final speaker = ref.read(turnSpeakerProvider);
    unawaited(wanted ? speaker.beginGuidance() : speaker.endGuidance());
  }

  void _forget() {
    _cancelRouting();
    _navigator = null;
    _announcer = null;
    _machine = null;
    _routeKey = null;
    _planKey = null;
    _machineKey = null;
    _planCumulative = const <double>[];
    _rideId = null;
    _fedSnapshot = null;
    _progress = null;
    _planAlongM = 0;
    _detours = 0;
    _offRouteState = OffRouteState.onRoute;
    _guidance = null;
  }
}

/// One routed way back onto the plan.
class _Rejoin {
  const _Rejoin({required this.result, required this.target});

  /// The way back itself.
  final RouteResult result;

  /// Where it meets the plan again.
  final RejoinTarget target;
}
