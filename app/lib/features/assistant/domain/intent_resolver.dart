import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

import '../../planner/domain/route_profile.dart';
import '../../planner/domain/waypoint.dart';
import '../../search/domain/search_result.dart';

/// The geocoding the resolver needs.
///
/// A one-method interface so the resolver stays free of HTTP and of Riverpod:
/// the app hands it a Photon-backed implementation, a test hands it a list of
/// canned answers.
abstract interface class PlaceGeocoder {
  /// Looks [query] up, biased towards [bias] when it is known.
  Future<List<SearchResult>> lookup(String query, {LatLng? bias, int limit});
}

/// A place name the model asked for, and where it turned out to be.
class ResolvedPlace {
  /// Creates a resolved place.
  const ResolvedPlace({
    required this.query,
    required this.label,
    required this.position,
  });

  /// Builds one from a geocoder result for [query].
  factory ResolvedPlace.from(String query, SearchResult result) =>
      ResolvedPlace(
        query: query,
        label: result.subtitle.isEmpty
            ? result.name
            : '${result.name}, ${result.subtitle}',
        position: result.position,
      );

  /// The name as the model wrote it, which is also the key a choice is made
  /// under.
  final String query;

  /// What to show the rider: the geocoder's name with its region.
  final String label;

  /// Where it is.
  final LatLng position;

  @override
  bool operator ==(Object other) =>
      other is ResolvedPlace &&
      other.query == query &&
      other.label == label &&
      other.position == position;

  @override
  int get hashCode => Object.hash(query, label, position);

  @override
  String toString() => 'ResolvedPlace($query -> $label)';
}

/// One name the geocoder answered with several places far apart.
class PlaceChoice {
  /// Creates a choice.
  const PlaceChoice({required this.query, required this.options});

  /// The name the model asked for.
  final String query;

  /// The places to choose between, best first.
  final List<ResolvedPlace> options;

  @override
  String toString() => 'PlaceChoice($query, ${options.length} options)';
}

/// Why a request could not be turned into a route.
enum UnresolvedReason {
  /// The model said it was not sure, so the app asks a follow-up itself
  /// rather than spending another call.
  lowConfidence,

  /// The route should start where the rider is, but no position is known.
  startUnknown,

  /// A place name produced no result at all.
  placeNotFound,

  /// A point-to-point request without a destination.
  destinationUnknown,

  /// This build has no geocoder, so names cannot be looked up.
  noGeocoder,
}

/// What [IntentResolver.resolve] made of a [RouteRequest].
sealed class ResolvedIntent {
  /// Creates a resolved intent.
  const ResolvedIntent({this.notes});

  /// The model's own note, when it left one.
  final String? notes;
}

/// A loop, ready for `SmartLoopController.start`.
final class LoopIntent extends ResolvedIntent {
  /// Creates a loop intent.
  const LoopIntent({
    required this.request,
    required this.start,
    this.via = const <ResolvedPlace>[],
    super.notes,
  });

  /// The request the loop planner takes.
  final LoopRequest request;

  /// Where the loop starts; `null` when that is simply "here".
  final ResolvedPlace? start;

  /// The places the loop should pass, in order.
  final List<ResolvedPlace> via;

  /// The wanted length in kilometres, for the summary line.
  double get distanceKm => request.targetM / 1000;
}

/// A point-to-point route, ready for the planner.
final class RouteIntent extends ResolvedIntent {
  /// Creates a route intent.
  const RouteIntent({
    required this.waypoints,
    required this.profile,
    required this.distanceKm,
    this.places = const <ResolvedPlace>[],
    super.notes,
  });

  /// Start, vias and destination, in order.
  final List<Waypoint> waypoints;

  /// The profile the model suggested.
  final RouteProfile profile;

  /// The length the model had in mind, for the summary line. The router
  /// decides the real one.
  final double distanceKm;

  /// The named places among [waypoints], for the via chips.
  final List<ResolvedPlace> places;
}

/// One or more names were ambiguous; the rider has to pick.
final class AmbiguousIntent extends ResolvedIntent {
  /// Creates an ambiguous intent.
  const AmbiguousIntent({required this.choices, super.notes});

  /// One entry per ambiguous name.
  final List<PlaceChoice> choices;
}

/// Nothing could be built from the request.
final class UnresolvedIntent extends ResolvedIntent {
  /// Creates an unresolved intent.
  const UnresolvedIntent(this.reason, {this.name, super.notes});

  /// Why it failed.
  final UnresolvedReason reason;

  /// The place name that could not be found, for [UnresolvedReason
  /// .placeNotFound].
  final String? name;
}

/// Turns the relay's [RouteRequest] into something the app can route.
///
/// This is the whole "understanding" half of the assistant and it runs on the
/// phone: the model never returns coordinates, so every name it produced is
/// geocoded here, biased to where the rider is looking. Two rules keep the
/// result honest:
///
/// * a request the model was not confident about is never routed — the app
///   asks a follow-up locally instead of spending a second call;
/// * a name that matches several places far apart becomes a choice for the
///   rider rather than a guess.
class IntentResolver {
  /// Creates a resolver over [geocoder].
  const IntentResolver({
    required this.geocoder,
    this.minConfidence = 0.5,
    this.ambiguityDistanceM = 25000,
    this.maxChoices = 3,
    this.lookupLimit = 5,
  });

  /// Looks up place names.
  final PlaceGeocoder geocoder;

  /// Below this the request is not routed but questioned.
  final double minConfidence;

  /// Two results further apart than this make a name ambiguous.
  final double ambiguityDistanceM;

  /// How many options one choice offers at most.
  final int maxChoices;

  /// How many results to ask the geocoder for.
  final int lookupLimit;

  /// Resolves [request].
  ///
  /// [currentPosition] is the device position, used when the model asked to
  /// start "here". [bias] is where the map is looking, which biases the
  /// geocoder; it falls back to [currentPosition]. [picks] holds the choices
  /// the rider already made, keyed by the name the model used, so a second
  /// pass after a chooser chip resolves without asking again.
  Future<ResolvedIntent> resolve(
    RouteRequest request, {
    LatLng? currentPosition,
    LatLng? bias,
    Map<String, ResolvedPlace> picks = const <String, ResolvedPlace>{},
  }) async {
    if (request.confidence < minConfidence) {
      return UnresolvedIntent(
        UnresolvedReason.lowConfidence,
        notes: request.notes,
      );
    }

    final around = bias ?? currentPosition;
    final choices = <PlaceChoice>[];

    ResolvedPlace? start;
    if (!request.start.useCurrent) {
      final name = request.start.name?.trim() ?? '';
      if (name.isEmpty) {
        if (currentPosition == null) {
          return UnresolvedIntent(
            UnresolvedReason.startUnknown,
            notes: request.notes,
          );
        }
      } else {
        final lookup = await _lookup(name, around, picks);
        switch (lookup) {
          case _Found(:final place):
            start = place;
          case _Ambiguous(:final choice):
            choices.add(choice);
          case _Missing():
            return UnresolvedIntent(
              UnresolvedReason.placeNotFound,
              name: name,
              notes: request.notes,
            );
          case _NoGeocoder():
            return UnresolvedIntent(
              UnresolvedReason.noGeocoder,
              notes: request.notes,
            );
        }
      }
    } else if (currentPosition == null) {
      return UnresolvedIntent(
        UnresolvedReason.startUnknown,
        notes: request.notes,
      );
    }

    final via = <ResolvedPlace>[];
    for (final name in request.via) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      final lookup = await _lookup(trimmed, around, picks);
      switch (lookup) {
        case _Found(:final place):
          via.add(place);
        case _Ambiguous(:final choice):
          choices.add(choice);
        case _Missing():
          return UnresolvedIntent(
            UnresolvedReason.placeNotFound,
            name: trimmed,
            notes: request.notes,
          );
        case _NoGeocoder():
          return UnresolvedIntent(
            UnresolvedReason.noGeocoder,
            notes: request.notes,
          );
      }
    }

    if (choices.isNotEmpty) {
      return AmbiguousIntent(choices: choices, notes: request.notes);
    }

    final startPosition = start?.position ?? currentPosition;
    if (startPosition == null) {
      return UnresolvedIntent(
        UnresolvedReason.startUnknown,
        notes: request.notes,
      );
    }

    if (request.loop) {
      return LoopIntent(
        request: LoopRequest(
          start: startPosition,
          via: via.map((p) => p.position).toList(growable: false),
          targetM: request.distanceKm * 1000,
          profile: profileFor(request.profileHint).engineName,
          prefs: prefsFor(request),
        ),
        start: start,
        via: via,
        notes: request.notes,
      );
    }

    // `propose_route` has no `end` field: for a point-to-point the last via
    // *is* the destination, and everything before it is passed through on the
    // way. A request with no via at all therefore names nowhere to go.
    if (via.isEmpty) {
      return UnresolvedIntent(
        UnresolvedReason.destinationUnknown,
        notes: request.notes,
      );
    }

    return RouteIntent(
      waypoints: normalizeWaypointKinds([
        Waypoint(pos: startPosition, name: start?.label),
        for (final place in via)
          Waypoint(pos: place.position, name: place.label),
      ]),
      profile: profileFor(request.profileHint),
      distanceKm: request.distanceKm,
      places: [?start, ...via],
      notes: request.notes,
    );
  }

  Future<_Lookup> _lookup(
    String name,
    LatLng? bias,
    Map<String, ResolvedPlace> picks,
  ) async {
    final picked = picks[name] ?? picks[name.toLowerCase()];
    if (picked != null) return _Found(picked);

    final List<SearchResult> results;
    try {
      results = await geocoder.lookup(name, bias: bias, limit: lookupLimit);
    } on Object {
      // A geocoder that cannot be reached is indistinguishable from one that
      // is not configured, as far as the rider is concerned.
      return const _NoGeocoder();
    }
    if (results.isEmpty) return const _Missing();

    final first = ResolvedPlace.from(name, results.first);
    final far = results
        .skip(1)
        .where(
          (r) =>
              haversineMeters(first.position, r.position) > ambiguityDistanceM,
        )
        .toList(growable: false);
    if (far.isEmpty) return _Found(first);

    return _Ambiguous(
      PlaceChoice(
        query: name,
        options: [
          first,
          ...far.map((r) => ResolvedPlace.from(name, r)),
        ].take(maxChoices).toList(growable: false),
      ),
    );
  }
}

/// The planner profile the model's hint maps onto.
RouteProfile profileFor(ProfileHint hint) =>
    RouteProfile.fromName(hint.json, fallback: RouteProfile.trekking);

/// The loop preferences the model's answer maps onto.
///
/// `traffic_tolerance` is three-valued and `avoidTraffic` is a switch: only a
/// rider who explicitly accepts a lot of traffic gets busy roads weighted
/// normally, because a bike app that guesses wrong here puts someone on a
/// trunk road.
LoopPrefs prefsFor(RouteRequest request) => LoopPrefs(
  hills: switch (request.hills) {
    HillPreference.avoid => Hills.avoid,
    HillPreference.neutral => Hills.neutral,
    HillPreference.seek => Hills.seek,
  },
  surface: switch (request.surface) {
    SurfacePreference.paved => Surface.paved,
    SurfacePreference.mixed => Surface.mixed,
    SurfacePreference.gravel => Surface.gravel,
  },
  avoidTraffic: request.trafficTolerance != TrafficTolerance.high,
);

sealed class _Lookup {
  const _Lookup();
}

final class _Found extends _Lookup {
  const _Found(this.place);
  final ResolvedPlace place;
}

final class _Ambiguous extends _Lookup {
  const _Ambiguous(this.choice);
  final PlaceChoice choice;
}

final class _Missing extends _Lookup {
  const _Missing();
}

final class _NoGeocoder extends _Lookup {
  const _NoGeocoder();
}
