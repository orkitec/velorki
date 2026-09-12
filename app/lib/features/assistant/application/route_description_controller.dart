import 'dart:ui' as ui;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../../core/db/database.dart' show RouteSource;
import '../../../core/plus/plus_gate.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../data/ai_consent_controller.dart';
import '../domain/assistant_state.dart';
import 'assistant_controller.dart';

part 'route_description_controller.g.dart';

/// Whether a description may be generated for [route].
///
/// Strava's API terms forbid using their data for AI, so a route that came
/// from Strava never gets one — the button is not shown at all.
bool canDescribe(SavedRoute route) => route.source != RouteSource.strava;

/// The state of one "Describe this route" run.
class RouteDescriptionState {
  /// Creates the state.
  const RouteDescriptionState({
    this.running = false,
    this.text = '',
    this.saved = false,
    this.problem,
  });

  /// Whether the model is still writing.
  final bool running;

  /// What has arrived so far, deltas concatenated.
  final String text;

  /// Whether [text] was written to the route.
  final bool saved;

  /// Why it failed, when it did.
  final AssistantProblem? problem;

  /// Whether there is something worth saving.
  bool get canSave => !running && text.trim().isNotEmpty && !saved;

  /// Copies with the given changes.
  RouteDescriptionState copyWith({
    bool? running,
    String? text,
    bool? saved,
    AssistantProblem? problem,
    bool clearProblem = false,
  }) => RouteDescriptionState(
    running: running ?? this.running,
    text: text ?? this.text,
    saved: saved ?? this.saved,
    problem: clearProblem ? null : (problem ?? this.problem),
  );
}

/// "Describe this route": one `step=describe` call, streamed into the sheet.
///
/// The model is given numbers, not geometry: distance, climbing, the surface
/// shares and the waypoint names. That keeps the prompt small and means no
/// track ever leaves the phone.
@riverpod
class RouteDescriptionController extends _$RouteDescriptionController {
  @override
  RouteDescriptionState build() => const RouteDescriptionState();

  /// Asks the model to describe [route] and streams the answer into the state.
  Future<void> describe(SavedRoute route, {String? locale}) async {
    if (state.running) return;
    state = const RouteDescriptionState(running: true);

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

    final buffer = StringBuffer();
    try {
      await for (final event in relay.planStream(
        step: describeStep,
        // The description step needs no prompt of its own: the summary is the
        // input, and the relay's own system prompt says what to do with it.
        prompt: route.name,
        locale: locale ?? ui.PlatformDispatcher.instance.locale.toLanguageTag(),
        routeSummary: summaryOf(route),
      )) {
        switch (event) {
          case TextEvent(:final delta):
            buffer.write(delta);
            state = state.copyWith(text: buffer.toString());
          case ErrorEvent(:final error):
            _fail(problemFor(RelayException(error, statusCode: 200)));
            return;
          case RouteRequestEvent():
          case DoneEvent():
            break;
        }
      }
    } on RelayException catch (e) {
      _fail(problemFor(e));
      return;
    } on Object catch (e) {
      _fail(AssistantProblem(AssistantFailure.relay, message: e.toString()));
      return;
    }
    state = state.copyWith(running: false);
  }

  /// Writes what the model wrote to the route's `description` column.
  Future<void> save(SavedRoute route) async {
    final text = state.text.trim();
    if (text.isEmpty) return;
    await ref
        .read(routeRepositoryProvider)
        .setDescription(route.id, text, aiGenerated: true);
    state = state.copyWith(saved: true);
  }

  void _fail(AssistantProblem problem) =>
      state = state.copyWith(running: false, problem: problem);
}

/// The compact summary the `describe` step is given.
RouteSummary summaryOf(SavedRoute route) {
  final stats = route.surfaceStats;
  return RouteSummary(
    distanceKm: route.distanceM / 1000,
    ascentM: route.ascentM,
    surface: stats == null
        ? const SurfaceMix()
        : SurfaceMix(paved: stats.pavedShare, unpaved: stats.unpavedShare),
    waypoints: route.waypoints
        .map((w) => w.name)
        .whereType<String>()
        .toList(growable: false),
  );
}
