import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/assistant/domain/intent_resolver.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

import 'support/fakes.dart';

const LatLng _here = LatLng(48.137213, 11.575612);

void main() {
  group('loops', () {
    test(
      'a loop from here becomes a LoopRequest with the model\'s prefs',
      () async {
        final geocoder = FakeGeocoder({
          'Starnberger See': [place('Starnberger See', 47.90, 11.30)],
        });
        final resolver = IntentResolver(geocoder: geocoder);

        final intent = await resolver.resolve(
          routeRequest(
            distanceKm: 65,
            via: ['Starnberger See'],
            hills: HillPreference.seek,
            surface: SurfacePreference.gravel,
            trafficTolerance: TrafficTolerance.low,
            profileHint: ProfileHint.gravel,
          ),
          currentPosition: _here,
        );

        final loop = intent as LoopIntent;
        expect(loop.request.start, _here);
        expect(loop.request.targetM, 65000);
        expect(loop.request.profile, 'gravel');
        expect(loop.request.via.single, const LatLng(47.90, 11.30));
        expect(loop.request.prefs.hills, Hills.seek);
        expect(loop.request.prefs.surface, Surface.gravel);
        expect(loop.request.prefs.avoidTraffic, isTrue);
        expect(loop.via.single.label, 'Starnberger See');
        expect(loop.distanceKm, 65);
      },
    );

    test(
      'a rider who accepts heavy traffic stops avoiding busy roads',
      () async {
        final resolver = IntentResolver(geocoder: FakeGeocoder());

        final intent = await resolver.resolve(
          routeRequest(trafficTolerance: TrafficTolerance.high),
          currentPosition: _here,
        );

        expect((intent as LoopIntent).request.prefs.avoidTraffic, isFalse);
      },
    );

    test('a named start is geocoded, biased to the map', () async {
      final geocoder = FakeGeocoder({
        'Freiburg': [place('Freiburg', 47.995, 7.85, city: 'Baden')],
      });
      final resolver = IntentResolver(geocoder: geocoder);

      final intent = await resolver.resolve(
        routeRequest(
          start: const RouteStart(useCurrent: false, name: 'Freiburg'),
        ),
        currentPosition: _here,
        bias: const LatLng(48.0, 7.8),
      );

      final loop = intent as LoopIntent;
      expect(loop.request.start, const LatLng(47.995, 7.85));
      expect(loop.start?.label, 'Freiburg, Baden');
      expect(geocoder.biases.single, const LatLng(48.0, 7.8));
    });
  });

  group('point to point', () {
    test('start, vias and the last via as the destination', () async {
      final geocoder = FakeGeocoder({
        'Tegernsee': [place('Tegernsee', 47.71, 11.75)],
        'Bad Tölz': [place('Bad Tölz', 47.76, 11.56)],
      });
      final resolver = IntentResolver(geocoder: geocoder);

      final intent = await resolver.resolve(
        routeRequest(
          loop: false,
          via: ['Bad Tölz', 'Tegernsee'],
          profileHint: ProfileHint.fastbike,
        ),
        currentPosition: _here,
      );

      final route = intent as RouteIntent;
      expect(route.profile, RouteProfile.fastbike);
      expect(route.waypoints.map((w) => w.kind), [
        WaypointKind.start,
        WaypointKind.via,
        WaypointKind.end,
      ]);
      expect(route.waypoints.first.pos, _here);
      expect(route.waypoints.last.pos, const LatLng(47.71, 11.75));
      expect(route.places.map((p) => p.label), ['Bad Tölz', 'Tegernsee']);
    });

    test('a point-to-point without a destination cannot be routed', () async {
      final resolver = IntentResolver(geocoder: FakeGeocoder());

      final intent = await resolver.resolve(
        routeRequest(loop: false),
        currentPosition: _here,
      );

      expect(
        (intent as UnresolvedIntent).reason,
        UnresolvedReason.destinationUnknown,
      );
    });
  });

  group('ambiguity', () {
    test('two places far apart become a choice, not a guess', () async {
      final geocoder = FakeGeocoder({
        'Neustadt': [
          place('Neustadt', 49.35, 8.14, city: 'Rheinland-Pfalz'),
          place('Neustadt', 50.73, 10.90, city: 'Thüringen'),
        ],
      });
      final resolver = IntentResolver(geocoder: geocoder);
      final request = routeRequest(via: ['Neustadt']);

      final intent = await resolver.resolve(request, currentPosition: _here);

      final choice = (intent as AmbiguousIntent).choices.single;
      expect(choice.query, 'Neustadt');
      expect(choice.options.map((o) => o.label), [
        'Neustadt, Rheinland-Pfalz',
        'Neustadt, Thüringen',
      ]);

      // Picking one resolves without asking the geocoder again.
      final picked = await resolver.resolve(
        request,
        currentPosition: _here,
        picks: {'Neustadt': choice.options.last},
      );
      expect(
        (picked as LoopIntent).request.via.single,
        const LatLng(50.73, 10.90),
      );
      expect(geocoder.queries, ['Neustadt']);
    });

    test('several results in the same town are not ambiguous', () async {
      final geocoder = FakeGeocoder({
        'Marienplatz': [
          place('Marienplatz', 48.137, 11.575),
          place('Marienplatz', 48.139, 11.577),
        ],
      });
      final resolver = IntentResolver(geocoder: geocoder);

      final intent = await resolver.resolve(
        routeRequest(via: ['Marienplatz']),
        currentPosition: _here,
      );

      expect(intent, isA<LoopIntent>());
    });
  });

  group('refusals', () {
    test('low confidence is questioned locally, never routed', () async {
      final geocoder = FakeGeocoder();
      final resolver = IntentResolver(geocoder: geocoder);

      final intent = await resolver.resolve(
        routeRequest(confidence: 0.3, notes: 'No distance was given.'),
        currentPosition: _here,
      );

      final unresolved = intent as UnresolvedIntent;
      expect(unresolved.reason, UnresolvedReason.lowConfidence);
      expect(unresolved.notes, 'No distance was given.');
      // Nothing was looked up: a low-confidence answer costs no geocoding.
      expect(geocoder.queries, isEmpty);
    });

    test('a name nobody knows is reported with the name', () async {
      final resolver = IntentResolver(geocoder: FakeGeocoder());

      final intent = await resolver.resolve(
        routeRequest(via: ['Lac de Nulle Part']),
        currentPosition: _here,
      );

      final unresolved = intent as UnresolvedIntent;
      expect(unresolved.reason, UnresolvedReason.placeNotFound);
      expect(unresolved.name, 'Lac de Nulle Part');
    });

    test('"from here" without a position asks for one', () async {
      final resolver = IntentResolver(geocoder: FakeGeocoder());

      final intent = await resolver.resolve(routeRequest());

      expect(
        (intent as UnresolvedIntent).reason,
        UnresolvedReason.startUnknown,
      );
    });

    test('a geocoder that throws is reported as having none', () async {
      final geocoder = FakeGeocoder()..failure = StateError('no network');
      final resolver = IntentResolver(geocoder: geocoder);

      final intent = await resolver.resolve(
        routeRequest(via: ['Tegernsee']),
        currentPosition: _here,
      );

      expect((intent as UnresolvedIntent).reason, UnresolvedReason.noGeocoder);
    });
  });
}
