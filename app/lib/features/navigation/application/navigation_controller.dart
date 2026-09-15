import 'dart:async';

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
import '../presentation/turn_phrases.dart';
import '../../settings/data/units.dart';
import 'route_geometry.dart';
import 'turn_announcer.dart';
import 'turn_navigator.dart';

part 'navigation_controller.g.dart';

/// How long after a re-route attempt the next one may go out.
const Duration rerouteGap = Duration(seconds: 20);

/// The same after a failed attempt: longer, so a router that is down or out
/// of reach is asked again at a sensible pace.
const Duration rerouteRetryGap = Duration(seconds: 30);

/// How long a re-route request is given before it is abandoned.
const Duration rerouteTimeout = Duration(seconds: 20);

/// Slower than this and no re-route is asked for: a rider who has stopped is
/// reading the map or waiting at a light, not riding away from the route.
const double _rerouteMovingMps = 1;

/// Nearer than this to the original route and a detour has done its job.
const double _backOnPlanM = 30;

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
  });

  /// Identity of the route: the saved route's id, or, for a plan that was
  /// never saved, the shape of its geometry.
  final String key;

  /// The geometry the rider is matched against.
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
/// Only [NavigationController] writes this; everyone else reads it, and the
/// record screen draws it in place of the plan.
@Riverpod(keepAlive: true)
class DetourRoute extends _$DetourRoute {
  @override
  GuidedRoute? build() => null;

  /// Puts [route] in the navigator's hands, or takes the detour away again.
  void replace(GuidedRoute? route) => state = route;
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
/// The controller has no [BuildContext], so it looks the strings up by the
/// platform locale instead. A locale the app has no translation for falls back
/// to English. Tests override this provider to pin the language.
@Riverpod(keepAlive: true)
AppLocalizations navigationLocalizations(Ref ref) {
  try {
    return lookupAppLocalizations(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
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
/// It also repairs a ride that has gone astray: while the rider is off route
/// and still moving it asks the router for a way from where they are back to
/// the rest of the plan, and navigates that detour until the plan is under
/// their wheels again.
@Riverpod(keepAlive: true)
class NavigationController extends _$NavigationController {
  TurnNavigator? _navigator;
  TurnAnnouncer? _announcer;

  /// Identity of the route the navigator was built for: the detour while one
  /// is up, the plan otherwise.
  String? _routeKey;

  /// Identity of the plan itself, so a different route starts from scratch.
  String? _planKey;

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

  /// How far along the plan the rider was when last matched to it. A detour
  /// is planned from here on, so the corners already ridden are left alone.
  double _planAlongM = 0;

  /// Whether a re-route request is out right now.
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
    final settings = ref.read(navigationSettingsProvider);
    final plan = ref.read(guidedRouteProvider);
    final guided =
        recording.isRecording &&
        settings.turns &&
        (plan?.line.length ?? 0) >= 2;
    if (!guided || plan == null) {
      _stop();
      return null;
    }

    final snapshot = recording.snapshot;
    final position = snapshot?.lastPosition;

    // Another route, or another ride: an old detour belongs to neither.
    final rideId = snapshot?.rideId;
    if (plan.key != _planKey || (rideId != null && rideId != _rideId)) {
      _planKey = plan.key;
      if (rideId != null) _rideId = rideId;
      _planAlongM = 0;
      _detours = 0;
      _cancelRouting();
      _setDetour(null);
    }

    var detour = ref.read(detourRouteProvider);
    final newFix =
        snapshot != null &&
        position != null &&
        !identical(snapshot, _fedSnapshot);
    // Back on the road that was planned in the first place: the detour has
    // done its job, whether or not it ever reached its own end.
    if (newFix &&
        detour != null &&
        projectOnLine(plan.line, position).distanceM < _backOnPlanM) {
      _setDetour(null);
      detour = null;
    }

    final route = detour ?? plan;
    if (route.key != _routeKey) {
      _routeKey = route.key;
      _navigator = TurnNavigator(line: route.line, turns: route.turns);
      _announcer = TurnAnnouncer();
      _fedSnapshot = null;
      _progress = null;
    }
    _guiding = true;

    // Nothing new to match: keep showing what the last fix said.
    if (snapshot == null ||
        position == null ||
        identical(snapshot, _fedSnapshot)) {
      return _decorate(_progress);
    }
    _fedSnapshot = snapshot;

    final progress = _navigator!.update(position);
    _progress = progress;
    final cues = _announcer!.update(progress, speedMps: snapshot.speedMps);
    if (cues.isNotEmpty && settings.voice) _speak(cues);

    // On the plan itself, remember how far the rider got: that is where the
    // rest of the plan starts when a detour has to be worked out.
    if (detour == null && !progress.offRoute) _planAlongM = progress.alongM;
    if (settings.reroute) _considerReroute(plan, progress, snapshot, position);

    return _decorate(progress);
  }

  /// Adds the re-routing flag to [progress], which the navigator knows
  /// nothing about.
  NavigationProgress? _decorate(NavigationProgress? progress) =>
      progress?.withRerouting(_rerouting);

  /// Asks the router for a way back onto the plan, if this is the moment for
  /// it: the rider is off route, moving, and the last attempt is long enough
  /// ago that the next one is not simply the same question again.
  void _considerReroute(
    GuidedRoute plan,
    NavigationProgress progress,
    RecordingSnapshot snapshot,
    LatLng position,
  ) {
    if (!progress.offRoute || _rerouting) return;
    if (snapshot.speedMps <= _rerouteMovingMps) return;
    final now = ref.read(navigationClockProvider)();
    final last = _lastAttemptAt;
    if (last != null && now.difference(last) < _gap) return;
    final backend = ref.read(routingBackendProvider);
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
            (result) => _rerouted(generation, result),
            onError: (Object error) => _rerouteFailed(generation, error),
          ),
    );
  }

  /// Takes a fresh route on: from here the rider is guided along it until it
  /// meets the plan again.
  void _rerouted(int generation, RouteResult result) {
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
    _setDetour(
      GuidedRoute(
        key: 'detour:$_detours:${line.length}',
        line: line,
        turns: result.turns,
      ),
    );
    if (ref.read(navigationSettingsProvider).voice) {
      _speak(const <TurnCue>[TurnCue(kind: CueKind.rerouted)]);
    }
    _refresh();
  }

  /// A failed attempt changes nothing the rider can see: they are still off
  /// route, and the next attempt waits a little longer.
  void _rerouteFailed(int generation, Object error) {
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
    final l10n = ref.read(navigationLocalizationsProvider);
    final speaker = ref.read(turnSpeakerProvider);
    for (final cue in cues) {
      final phrase = cuePhrase(cue, l10n, units: ref.read(unitSystemProvider));
      if (phrase.isNotEmpty) unawaited(speaker.speak(phrase));
    }
  }

  /// Ends a guided ride: the detour, the navigator and the announcer go, and
  /// anything still queued in the speaker is dropped.
  void _stop() {
    _setDetour(null);
    _forget();
    if (!_guiding) return;
    _guiding = false;
    unawaited(ref.read(turnSpeakerProvider).stop());
  }

  void _forget() {
    _cancelRouting();
    _navigator = null;
    _announcer = null;
    _routeKey = null;
    _planKey = null;
    _rideId = null;
    _fedSnapshot = null;
    _progress = null;
    _planAlongM = 0;
    _detours = 0;
  }
}
