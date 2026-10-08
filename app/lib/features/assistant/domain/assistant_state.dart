import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_api/velorki_api.dart';

import 'intent_resolver.dart';

part 'assistant_state.freezed.dart';

/// Where the assistant is in one request.
enum AssistantPhase {
  /// Waiting for a prompt.
  idle,

  /// The relay is being asked.
  asking,

  /// The answer arrived and its place names are being looked up.
  resolving,

  /// A route or a loop search was handed over.
  ready,

  /// A name was ambiguous; the rider has to pick.
  needsChoice,

  /// Something went wrong, or the model was not sure.
  failed,
}

/// Why the assistant could not do what was asked.
enum AssistantFailure {
  /// The rider has no Velorki Plus.
  notEntitled,

  /// Consent is missing or was refused.
  consentRequired,

  /// This build has no relay configured.
  noRelay,

  /// This build has no geocoder configured.
  noGeocoder,

  /// The relay's per-user or per-IP limit was hit.
  rateLimited,

  /// The relay or the model failed.
  relay,

  /// The model was not confident enough to be routed.
  lowConfidence,

  /// A place name produced no result.
  placeNotFound,

  /// The route should start "here" and there is no position.
  startUnknown,

  /// A point-to-point request named no destination.
  destinationUnknown,

  /// There is no route on the map to ask about.
  noRoute,
}

/// One thing that went wrong, in the terms the sheet renders.
class AssistantProblem {
  /// Creates a problem.
  const AssistantProblem(
    this.failure, {
    this.message,
    this.relayCode,
    this.name,
    this.notes,
    this.retryAfterS,
  });

  /// What kind of problem it is.
  final AssistantFailure failure;

  /// The relay's own words, or the error, in English for the log.
  final String? message;

  /// The relay's error code, when the relay answered with one; it is what
  /// the sheet words.
  final String? relayCode;

  /// The place name that could not be found.
  final String? name;

  /// The model's note, shown with a low-confidence answer.
  final String? notes;

  /// How long to wait, from a `rate_limited` error.
  final int? retryAfterS;

  @override
  bool operator ==(Object other) =>
      other is AssistantProblem &&
      other.failure == failure &&
      other.message == message &&
      other.relayCode == relayCode &&
      other.name == name &&
      other.notes == notes &&
      other.retryAfterS == retryAfterS;

  @override
  int get hashCode =>
      Object.hash(failure, message, relayCode, name, notes, retryAfterS);

  @override
  String toString() => 'AssistantProblem(${failure.name}, $message)';
}

/// Everything the assistant sheet shows about one request.
@freezed
abstract class AssistantState with _$AssistantState {
  /// Creates the state.
  const factory AssistantState({
    /// Where the request has got to.
    @Default(AssistantPhase.idle) AssistantPhase phase,

    /// The prompt the rider sent, kept so "try again" can resend it.
    @Default('') String prompt,

    /// What the model proposed, before any geocoding.
    RouteRequest? request,

    /// What the resolver made of it.
    ResolvedIntent? intent,

    /// The names still to be picked, when [phase] is
    /// [AssistantPhase.needsChoice].
    @Default(<PlaceChoice>[]) List<PlaceChoice> choices,

    /// The choices the rider already made, keyed by the model's name.
    @Default(<String, ResolvedPlace>{}) Map<String, ResolvedPlace> picks,

    /// Why it failed, when it did.
    AssistantProblem? problem,
  }) = _AssistantState;

  const AssistantState._();

  /// Whether a request is in flight.
  bool get busy =>
      phase == AssistantPhase.asking || phase == AssistantPhase.resolving;

  /// The loop the assistant started, when it started one.
  LoopIntent? get loop => intent is LoopIntent ? intent! as LoopIntent : null;

  /// The point-to-point route the assistant handed to the planner.
  RouteIntent? get route =>
      intent is RouteIntent ? intent! as RouteIntent : null;
}
