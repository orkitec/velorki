import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/tables/routes.dart' show RouteSource;
import '../../../core/plus/plus_gate.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/domain/planner_state.dart';
import '../../planner/domain/route_poi.dart';
import '../../planner/domain/route_profile.dart';
import '../data/ai_consent_controller.dart';
import '../domain/assistant_state.dart';
import 'ai_request_settings.dart';
import 'assistant_sheet_memory.dart';
import 'assistant_controller.dart';
import 'route_description_controller.dart' show routeDigestTimeout;
import 'route_digest_service.dart';

part 'route_advice_controller.g.dart';

/// Whether the route on the planner's map may be asked about.
///
/// There has to be a route, and it must not have come from Strava: their
/// API terms forbid using their data for AI, so such a route is never sent.
bool canAskAboutRoute(PlannerState planner) {
  final route = planner.result;
  return route != null &&
      route.geometry.length >= 2 &&
      planner.savedRouteSource != RouteSource.strava;
}

/// Where a question about the route has got to.
enum RouteAdvicePhase {
  /// Waiting for a question.
  idle,

  /// The route's digest is being built on the phone.
  reading,

  /// The relay is being asked.
  asking,

  /// The answer is in.
  answered,

  /// Something went wrong.
  failed,
}

/// Why the fix of a finding could not be applied.
enum FixFailure {
  /// There is no route on the planner's map.
  noRoute,

  /// The fix does not fit the route on the map: the place is not in the
  /// digest, or the stretch is not on the route.
  notApplicable,

  /// The planner could not route with the fix, which was taken back.
  routingFailed,
}

/// The state of one question about the route on the map.
@immutable
class RouteAdviceState {
  /// Creates the state.
  const RouteAdviceState({
    this.phase = RouteAdvicePhase.idle,
    this.question = '',
    this.route,
    this.ends,
    this.digest,
    this.advice,
    this.applied = const <int>{},
    this.failures = const <int, FixFailure>{},
    this.problem,
  });

  /// Where it has got to.
  final RouteAdvicePhase phase;

  /// What the rider asked.
  final String question;

  /// The route that was asked about, as it was on the map.
  final RouteResult? route;

  /// Where the plan that was asked about starts and ends. The conversation
  /// lasts while the planner's plan does: the fixes add stops and change the
  /// way, never the ends, and a plan with other ends is another route.
  final (LatLng, LatLng)? ends;

  /// The digest that was sent, whose place ids the answer refers to.
  final RouteDigest? digest;

  /// The answer, once it is in.
  final RouteAdvice? advice;

  /// The indices of the findings whose fix was applied.
  final Set<int> applied;

  /// The findings whose fix could not be applied, with why.
  final Map<int, FixFailure> failures;

  /// Why it failed, when it did.
  final AssistantProblem? problem;

  /// Whether a question is being worked on.
  bool get busy =>
      phase == RouteAdvicePhase.reading || phase == RouteAdvicePhase.asking;

  /// Whether there is anything to start over from.
  bool get isEmpty =>
      phase == RouteAdvicePhase.idle && question.isEmpty && advice == null;

  /// The place of the digest with [id], or `null`.
  DigestPlace? placeOf(String? id) {
    if (id == null) return null;
    for (final place in digest?.places ?? const <DigestPlace>[]) {
      if (place.id == id) return place;
    }
    return null;
  }

  /// Copies with the given changes.
  RouteAdviceState copyWith({
    RouteAdvicePhase? phase,
    RouteDigest? digest,
    RouteAdvice? advice,
    Set<int>? applied,
    Map<int, FixFailure>? failures,
    AssistantProblem? problem,
  }) => RouteAdviceState(
    phase: phase ?? this.phase,
    question: question,
    route: route,
    ends: ends,
    digest: digest ?? this.digest,
    advice: advice ?? this.advice,
    applied: applied ?? this.applied,
    failures: failures ?? this.failures,
    problem: problem ?? this.problem,
  );
}

/// Where [planner]'s plan starts and ends, or `null` without one.
(LatLng, LatLng)? planEnds(PlannerState planner) {
  final points = planner.waypoints;
  if (points.length < 2) return null;
  return (points.first.pos, points.last.pos);
}

/// "This route": a question about the route on the planner's map, answered
/// from its digest, with fixes the planner can apply.
///
/// The same gates as the rest of the assistant — the build has a relay, the
/// rider holds Velorki Plus and consented — and no position goes along: the
/// route is what is asked about. The answer never changes the route by
/// itself; each fix is applied by the rider, through the planner, as one
/// undo step.
///
/// Kept while the sheet is closed, so the conversation is still there when
/// it opens again, for as long as the planner's plan is the one asked about
/// ([RouteAdviceState.ends]); a cleared plan or one with other ends starts
/// it afresh.
@Riverpod(keepAlive: true)
class RouteAdviceController extends _$RouteAdviceController {
  /// The fix being routed: its finding, and how deep the planner's undo
  /// stack was with it on top.
  ({int index, int undoDepth})? _routing;

  @override
  RouteAdviceState build() {
    ref.listen(plannerControllerProvider, (_, next) => _planChanged(next));
    return const RouteAdviceState();
  }

  void _planChanged(PlannerState plan) {
    final asked = state.ends;
    if (asked != null && planEnds(plan) != asked && !state.busy) {
      // Another route: what was asked and typed about the last one goes.
      _routing = null;
      ref.read(assistantSheetMemoryProvider).question = '';
      state = const RouteAdviceState();
      return;
    }
    final routing = _routing;
    if (routing == null || plan.isRouting) return;
    _routing = null;
    if (!plan.route.hasError) return;
    // The fix took the route somewhere the router could not follow: take it
    // back, unless the rider has changed the plan since, and say so.
    if (plan.undoStack.length == routing.undoDepth) {
      ref.read(plannerControllerProvider.notifier).undo();
    }
    state = state.copyWith(
      applied: {...state.applied}..remove(routing.index),
      failures: {...state.failures, routing.index: FixFailure.routingFailed},
    );
  }

  /// Forgets the question, the answer and its fixes.
  void reset() {
    if (state.busy) return;
    _routing = null;
    state = const RouteAdviceState();
  }

  /// Asks [question] about the route on the planner's map.
  Future<void> ask(String question, {String? locale}) async {
    final text = question.trim();
    if (text.isEmpty || state.busy) return;
    final planner = ref.read(plannerControllerProvider);
    final route = planner.result;
    _routing = null;
    state = RouteAdviceState(
      phase: RouteAdvicePhase.reading,
      question: text,
      route: route,
      ends: planEnds(planner),
    );

    if (!ref.read(plusFeatureProvider(PlusFeature.aiAssistant))) {
      _fail(const AssistantProblem(AssistantFailure.notEntitled));
      return;
    }
    final relay = ref.read(relayClientProvider);
    if (relay == null) {
      _fail(const AssistantProblem(AssistantFailure.noRelay));
      return;
    }
    final consent = ref.read(aiConsentControllerProvider);
    if (consent == null || !consent.allowsRequests) {
      _fail(const AssistantProblem(AssistantFailure.consentRequired));
      return;
    }
    if (route == null || !canAskAboutRoute(planner)) {
      _fail(const AssistantProblem(AssistantFailure.noRoute));
      return;
    }

    final digest = await _digest(route, planner);
    if (!ref.mounted) return;
    state = state.copyWith(phase: RouteAdvicePhase.asking, digest: digest);

    RouteAdvice? advice;
    try {
      await for (final event in relay.planStream(
        step: routeStep,
        prompt: text,
        locale: locale ?? ref.read(aiLocaleTagProvider),
        units: ref.read(aiUnitsProvider),
        routeSummary: summaryOfPlan(planner, route, digest),
      )) {
        switch (event) {
          case RouteAdviceEvent(advice: final answer):
            advice = answer;
          case ErrorEvent(:final error):
            throw RelayException(error, statusCode: 200);
          case RouteRequestEvent():
          case TextEvent():
          case DoneEvent():
            break;
        }
      }
    } on RelayException catch (e) {
      if (ref.mounted) _fail(problemFor(e));
      return;
    } on Object catch (e) {
      if (ref.mounted) {
        _fail(AssistantProblem(AssistantFailure.relay, message: e.toString()));
      }
      return;
    }
    if (!ref.mounted) return;
    if (advice == null) {
      _fail(const AssistantProblem(AssistantFailure.relay));
      return;
    }
    state = state.copyWith(
      phase: RouteAdvicePhase.answered,
      advice: _withKnownPlaces(advice, digest),
    );
  }

  /// Applies the fix of finding [index] through the planner, as one undo
  /// step, and marks it applied; or, when it cannot be applied, says why in
  /// [RouteAdviceState.failures]. A fix the planner then cannot route is
  /// taken back and marked failed too.
  ///
  /// A stop goes in where the route passes the place: at the place's
  /// distance along the route that was asked about while that route is
  /// still the one on the map, else wherever the current route comes
  /// closest to it.
  ///
  /// `true` when the fix went to the planner.
  bool apply(int index) {
    final findings = state.advice?.findings ?? const <RouteFinding>[];
    if (index < 0 || index >= findings.length) return false;
    if (state.applied.contains(index)) return false;
    final fix = findings[index].fix;
    if (fix == null) return false;
    final planner = ref.read(plannerControllerProvider.notifier);
    final current = ref.read(plannerControllerProvider).result;
    if (current == null) return _failed(index, FixFailure.noRoute);
    final unchanged = identical(current, state.route);
    final done = switch (fix) {
      AddStopFix(:final placeId) => switch (state.placeOf(placeId)) {
        null => false,
        final place => planner.insertStop(
          LatLng(place.at.lat, place.at.lon),
          alongM: unchanged ? place.km * 1000 : null,
          name: place.name,
          poiKind: poiKindOfPlace(place.kind),
        ),
      },
      AvoidFix(:final fromKm, :final toKm) => planner.avoidStretch(
        fromKm * 1000,
        toKm * 1000,
      ),
      ProfileFix(:final profile) => () {
        planner.setProfile(RouteProfile.fromName(profile.json));
        return true;
      }(),
    };
    if (!done) return _failed(index, FixFailure.notApplicable);
    final plan = ref.read(plannerControllerProvider);
    if (plan.isRouting) {
      _routing = (index: index, undoDepth: plan.undoStack.length);
    }
    state = state.copyWith(
      applied: <int>{...state.applied, index},
      failures: {...state.failures}..remove(index),
    );
    return true;
  }

  bool _failed(int index, FixFailure failure) {
    state = state.copyWith(failures: {...state.failures, index: failure});
    return false;
  }

  /// Drops the error but keeps the question, for "try again".
  void clearProblem() {
    if (state.problem == null) return;
    state = RouteAdviceState(question: state.question, ends: state.ends);
  }

  /// The digest of [route], or a bare one — the loop flag and the profile —
  /// when the phone has nothing more to tell in time: the question still
  /// goes, on the figures alone.
  Future<RouteDigest> _digest(RouteResult route, PlannerState planner) async {
    final profile = planner.options.profile.brouterName;
    try {
      final digest = await ref
          .read(routeDigestServiceProvider)
          .digestOfTrack(
            geometry: route.geometry,
            distanceM: route.lengthM,
            profile: profile,
            messages: route.messages,
            keepEmpty: true,
          )
          .timeout(routeDigestTimeout);
      if (digest != null) return digest;
    } on Object catch (e) {
      debugPrint('velorki: no digest for the planned route: $e');
    }
    return RouteDigest(loop: planner.isClosedLoop, profile: profile);
  }

  void _fail(AssistantProblem problem) =>
      state = state.copyWith(phase: RouteAdvicePhase.failed, problem: problem);
}

/// [advice] without the fixes that name a place [digest] does not have.
///
/// The relay already refuses such an answer; this keeps a relay that does
/// not from putting a stop nowhere.
RouteAdvice _withKnownPlaces(RouteAdvice advice, RouteDigest digest) {
  final ids = {for (final p in digest.places) p.id};
  return RouteAdvice(
    answer: advice.answer,
    findings: [
      for (final f in advice.findings)
        switch (f.fix) {
          AddStopFix(:final placeId) when !ids.contains(placeId) =>
            RouteFinding(
              kind: f.kind,
              text: f.text,
              fromKm: f.fromKm,
              toKm: f.toKm,
              placeId: f.placeId,
            ),
          _ => f,
        },
    ],
  );
}

/// The summary a question about the planner's [route] is sent with.
///
/// Its distance is never shorter than the line the digest measured along,
/// so no place of the digest lies past the route's end.
RouteSummary summaryOfPlan(
  PlannerState planner,
  RouteResult route,
  RouteDigest digest,
) {
  final stats = planner.surfaceStats;
  final line = cumulativeDistancesMeters(route.positions);
  final lengthM = math.max(route.lengthM, line.isEmpty ? 0.0 : line.last);
  return RouteSummary(
    distanceKm: lengthM / 1000,
    ascentM: route.ascentM,
    surface: stats == null
        ? const SurfaceMix()
        : SurfaceMix(paved: stats.pavedShare, unpaved: stats.unpavedShare),
    waypoints: planner.waypoints
        .map((w) => w.name)
        .whereType<String>()
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        // The relay takes at most 50 names of 120 characters.
        .map((n) => n.length > 120 ? n.substring(0, 120) : n)
        .take(50)
        .toList(growable: false),
    digest: digest,
  );
}

/// The marker a stop at a digest place of [kind] gets.
PoiKind poiKindOfPlace(String kind) => switch (kind) {
  'cafe' || 'bakery' => PoiKind.food,
  'drinking_water' || 'water' => PoiKind.water,
  'toilets' => PoiKind.toilet,
  'viewpoint' => PoiKind.viewpoint,
  'bicycle_shop' || 'bicycle_repair_station' => PoiKind.repair,
  _ => PoiKind.generic,
};
