import 'dart:async';
import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/plus/plus_gate.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/domain/route_profile.dart';
import '../../planner/domain/waypoint.dart';
import '../../smart_loop/application/smart_loop_controller.dart';
import '../data/ai_consent_controller.dart';
import '../data/place_geocoder.dart';
import '../domain/ai_consent.dart';
import '../domain/assistant_state.dart';
import '../domain/intent_resolver.dart';

part 'assistant_controller.g.dart';

final Logger _log = Logger('Assistant');

/// The `step` value of a planning request.
const String planStep = 'plan';

/// The `step` value of a description request.
const String describeStep = 'describe';

/// The assistant's state machine.
///
/// One request at a time, and four gates before anything leaves the phone:
/// the build has a relay, the rider holds Velorki Plus, the rider consented,
/// and — only if they consented to it — a position exists to round and send.
/// What comes back is structured, never a route: the geometry is computed on
/// the phone, by the loop planner or by the normal planner.
@Riverpod(keepAlive: true)
class AssistantController extends _$AssistantController {
  @override
  AssistantState build() => const AssistantState();

  /// Asks the model for a route and hands the answer to the planner.
  ///
  /// [position] is the device position, already known to the caller (the sheet
  /// asks for the location permission the same way the loop sheet does), and
  /// [bias] is where the map is looking, which biases the geocoder. Neither is
  /// sent anywhere unless the consent is [AiConsent.withLocation], and then
  /// only rounded to [aiPositionDecimals] decimals.
  Future<void> submit(
    String prompt, {
    LatLng? position,
    LatLng? bias,
    String? locale,
  }) async {
    final text = prompt.trim();
    if (text.isEmpty || state.busy) return;

    state = AssistantState(prompt: text, phase: AssistantPhase.asking);

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

    final RouteRequest? request;
    try {
      request = await _ask(
        relay,
        text,
        consent: consent,
        position: position,
        locale: locale,
      );
    } on RelayException catch (e) {
      _fail(problemFor(e));
      return;
    } on Object catch (e, st) {
      _log.warning('the assistant request failed', e, st);
      _fail(AssistantProblem(AssistantFailure.relay, message: e.toString()));
      return;
    }
    if (request == null) {
      _fail(const AssistantProblem(AssistantFailure.relay));
      return;
    }

    state = state.copyWith(
      request: request,
      phase: AssistantPhase.resolving,
      problem: null,
    );
    await _resolveAndApply(position: position, bias: bias);
  }

  /// Records the rider's answer to a chooser chip and resolves again.
  ///
  /// No second model call: the structured request is still in the state, only
  /// the geocoding changes.
  Future<void> choose(
    String query,
    ResolvedPlace place, {
    LatLng? position,
    LatLng? bias,
  }) async {
    if (state.request == null) return;
    state = state.copyWith(
      picks: <String, ResolvedPlace>{...state.picks, query: place},
      phase: AssistantPhase.resolving,
    );
    await _resolveAndApply(position: position, bias: bias);
  }

  /// Clears everything, so the sheet is back to an empty field.
  void reset() => state = const AssistantState();

  /// Drops the error but keeps the prompt, for "try again".
  void clearProblem() {
    if (state.problem == null) return;
    state = state.copyWith(problem: null, phase: AssistantPhase.idle);
  }

  /// Runs one `POST /ai/plan` with `step=plan` and returns what the model
  /// proposed.
  ///
  /// The stream carries exactly one `route_request`; an `error` event is
  /// raised as the [RelayException] it would have been had it arrived before
  /// the stream opened.
  Future<RouteRequest?> _ask(
    RelayClient relay,
    String prompt, {
    required AiConsent consent,
    LatLng? position,
    String? locale,
  }) async {
    await for (final event in relay.planStream(
      step: planStep,
      prompt: prompt,
      locale: locale ?? ui.PlatformDispatcher.instance.locale.toLanguageTag(),
      context: contextFor(consent: consent, position: position),
    )) {
      switch (event) {
        case RouteRequestEvent(:final request):
          return request;
        case ErrorEvent(:final error):
          throw RelayException(error, statusCode: 200);
        case TextEvent():
        case DoneEvent():
          break;
      }
    }
    return null;
  }

  Future<void> _resolveAndApply({LatLng? position, LatLng? bias}) async {
    final request = state.request;
    if (request == null) return;
    final resolver = ref.read(intentResolverProvider);
    if (resolver == null) {
      _fail(const AssistantProblem(AssistantFailure.noGeocoder));
      return;
    }

    final intent = await resolver.resolve(
      request,
      currentPosition: position,
      bias: bias,
      picks: state.picks,
    );

    switch (intent) {
      case AmbiguousIntent(:final choices):
        state = state.copyWith(
          intent: intent,
          choices: choices,
          phase: AssistantPhase.needsChoice,
          problem: null,
        );
      case UnresolvedIntent(:final reason, :final name, :final notes):
        _fail(
          AssistantProblem(
            switch (reason) {
              UnresolvedReason.lowConfidence => AssistantFailure.lowConfidence,
              UnresolvedReason.startUnknown => AssistantFailure.startUnknown,
              UnresolvedReason.placeNotFound => AssistantFailure.placeNotFound,
              UnresolvedReason.destinationUnknown =>
                AssistantFailure.destinationUnknown,
              UnresolvedReason.noGeocoder => AssistantFailure.noGeocoder,
            },
            name: name,
            notes: notes,
          ),
          intent: intent,
        );
      case LoopIntent(:final request, :final via):
        _ready(intent);
        if (via.isEmpty) {
          // Nothing to ride past, so BRouter's round-trip mode makes the loop.
          // Fire and forget: the search reports its own progress and the
          // assistant sheet closes onto the loop sheet as soon as this
          // returns.
          unawaited(
            ref.read(smartLoopControllerProvider.notifier).search(request),
          );
        } else {
          // The places to ride past *are* the route; closing it is what makes
          // it a loop, and the way home avoids the way out.
          ref.read(plannerControllerProvider.notifier)
            ..setProfile(RouteProfile.fromName(request.profile))
            ..setWaypoints(<Waypoint>[
              Waypoint(pos: request.start),
              for (final place in via)
                Waypoint(pos: place.position, name: place.label),
            ])
            ..closeLoop(differentWayBack: true);
        }
      case RouteIntent():
        ref.read(plannerControllerProvider.notifier)
          ..setProfile(intent.profile)
          ..setWaypoints(intent.waypoints);
        _ready(intent);
    }
  }

  void _ready(ResolvedIntent intent) {
    state = state.copyWith(
      intent: intent,
      choices: const <PlaceChoice>[],
      phase: AssistantPhase.ready,
      problem: null,
    );
  }

  void _fail(AssistantProblem problem, {ResolvedIntent? intent}) {
    state = state.copyWith(
      problem: problem,
      intent: intent,
      phase: AssistantPhase.failed,
    );
  }
}

/// What the model is told about the rider's situation.
///
/// Only ever a rounded position, and only with [AiConsent.withLocation].
/// `start_label` would need a reverse geocode for one line of prompt, so it
/// is deliberately left out.
PlanContext? contextFor({required AiConsent consent, LatLng? position}) {
  if (!consent.allowsLocation || position == null) return null;
  return PlanContext(
    start: PlanStart(
      lat: roundCoordinate(position.lat),
      lon: roundCoordinate(position.lon),
    ),
  );
}

/// Maps a relay failure onto the assistant's own problem kinds.
AssistantProblem problemFor(RelayException e) => switch (e.error.code) {
  RelayErrorCode.notEntitled => AssistantProblem(
    AssistantFailure.notEntitled,
    message: e.error.message,
  ),
  RelayErrorCode.consentRequired => AssistantProblem(
    AssistantFailure.consentRequired,
    message: e.error.message,
  ),
  RelayErrorCode.rateLimited => AssistantProblem(
    AssistantFailure.rateLimited,
    message: e.error.message,
    retryAfterS: e.error.retryAfterS,
  ),
  _ => AssistantProblem(AssistantFailure.relay, message: e.error.message),
};
