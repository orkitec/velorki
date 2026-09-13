import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/assistant_controller.dart';
import 'package:velorki/features/assistant/data/place_geocoder.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/domain/assistant_state.dart';
import 'package:velorki/features/assistant/domain/intent_resolver.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../integrations/support/fakes.dart';
import '../smart_loop/support/fake_loop_backend.dart';
import 'support/fakes.dart';

const LatLng _here = LatLng(48.137213, 11.575612);

Future<ProviderContainer> _container({
  required FakeRelayClient relay,
  FakeGeocoder? geocoder,
  AiConsent? consent = AiConsent.withLocation,
  bool entitled = true,
  bool withRelay = true,
  List<Override> extraOverrides = const <Override>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (consent != null) aiConsentPrefsKey: consent.name,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      relayClientProvider.overrideWithValue(withRelay ? relay : null),
      intentResolverProvider.overrideWithValue(
        IntentResolver(geocoder: geocoder ?? FakeGeocoder()),
      ),
      routingBackendProvider.overrideWithValue(FakeLoopBackend()),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  container.read(plusEntitledProvider.notifier).value = entitled;
  return container;
}

void main() {
  group('submit', () {
    test('a loop request starts a loop search', () async {
      final relay = FakeRelayClient(
        planEvents: <PlanEvent>[
          RouteRequestEvent(routeRequest(distanceKm: 55)),
          const DoneEvent(),
        ],
      );
      final container = await _container(relay: relay);

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a 55 km loop from here', position: _here, locale: 'de-DE');

      final state = container.read(assistantControllerProvider);
      expect(state.phase, AssistantPhase.ready);
      expect(state.loop?.request.targetM, 55000);

      final loop = container.read(smartLoopControllerProvider);
      expect(loop.request?.targetM, 55000);
      expect(loop.request?.start, _here);

      final call = relay.planCalls.single;
      expect(call.step, 'plan');
      expect(call.prompt, 'a 55 km loop from here');
      expect(call.locale, 'de-DE');
    });

    test('a point-to-point request lands in the planner', () async {
      final relay = FakeRelayClient(
        planEvents: <PlanEvent>[
          RouteRequestEvent(routeRequest(loop: false, via: ['Tegernsee'])),
          const DoneEvent(),
        ],
      );
      final container = await _container(
        relay: relay,
        geocoder: FakeGeocoder({
          'Tegernsee': [place('Tegernsee', 47.71, 11.75)],
        }),
      );

      await container
          .read(assistantControllerProvider.notifier)
          .submit('take me to Tegernsee', position: _here);

      expect(
        container.read(assistantControllerProvider).phase,
        AssistantPhase.ready,
      );
      final planner = container.read(plannerControllerProvider);
      expect(planner.waypoints.map((w) => w.pos), [
        _here,
        const LatLng(47.71, 11.75),
      ]);
    });

    test('a loop past a place is plotted and closed', () async {
      final relay = FakeRelayClient(
        planEvents: <PlanEvent>[
          RouteRequestEvent(routeRequest(via: ['Tegernsee'])),
          const DoneEvent(),
        ],
      );
      final container = await _container(
        relay: relay,
        geocoder: FakeGeocoder({
          'Tegernsee': [place('Tegernsee', 47.71, 11.75)],
        }),
      );

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop past the Tegernsee', position: _here);

      // Nothing to search for: the place is the route, and closing it behind
      // the rider is what makes it a loop.
      expect(container.read(smartLoopControllerProvider).request, isNull);
      final planner = container.read(plannerControllerProvider);
      expect(planner.positions, <LatLng>[
        _here,
        const LatLng(47.71, 11.75),
        _here,
      ]);
      expect(planner.isClosedLoop, isTrue);
      expect(planner.options.differentWayBack, isTrue);
    });

    test('an ambiguous name waits for the rider, then resolves', () async {
      final relay = FakeRelayClient(
        planEvents: <PlanEvent>[
          RouteRequestEvent(routeRequest(via: ['Neustadt'])),
          const DoneEvent(),
        ],
      );
      final geocoder = FakeGeocoder({
        'Neustadt': [
          place('Neustadt', 49.35, 8.14, city: 'Rheinland-Pfalz'),
          place('Neustadt', 50.73, 10.90, city: 'Thüringen'),
        ],
      });
      final container = await _container(relay: relay, geocoder: geocoder);
      final controller = container.read(assistantControllerProvider.notifier);

      await controller.submit('a loop past Neustadt', position: _here);

      var state = container.read(assistantControllerProvider);
      expect(state.phase, AssistantPhase.needsChoice);
      final options = state.choices.single.options;
      expect(options, hasLength(2));

      await controller.choose('Neustadt', options.last, position: _here);

      state = container.read(assistantControllerProvider);
      expect(state.phase, AssistantPhase.ready);
      expect(state.loop?.request.via.single, const LatLng(50.73, 10.90));
      // The model was asked exactly once for the whole exchange.
      expect(relay.planCalls, hasLength(1));
    });
  });

  group('what is sent', () {
    test('consent with location sends a position rounded to ~1 km', () async {
      final relay = FakeRelayClient(
        planEvents: <PlanEvent>[
          RouteRequestEvent(routeRequest()),
          const DoneEvent(),
        ],
      );
      final container = await _container(relay: relay);

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop', position: _here);

      final start = relay.planCalls.single.context!.start!;
      expect(start.lat, 48.14);
      expect(start.lon, 11.58);
    });

    test('text-only consent sends no position at all', () async {
      final relay = FakeRelayClient(
        planEvents: <PlanEvent>[
          RouteRequestEvent(routeRequest()),
          const DoneEvent(),
        ],
      );
      final container = await _container(
        relay: relay,
        consent: AiConsent.textOnly,
      );

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop', position: _here);

      expect(relay.planCalls.single.context, isNull);
      // The position is still used locally: the loop starts where the rider is.
      expect(container.read(smartLoopControllerProvider).request?.start, _here);
    });
  });

  group('gates', () {
    test('without Velorki Plus nothing is sent', () async {
      final relay = FakeRelayClient();
      final container = await _container(relay: relay, entitled: false);

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop', position: _here);

      final state = container.read(assistantControllerProvider);
      expect(state.phase, AssistantPhase.failed);
      expect(state.problem?.failure, AssistantFailure.notEntitled);
      expect(relay.planCalls, isEmpty);
    });

    test('without consent nothing is sent', () async {
      final relay = FakeRelayClient();
      final container = await _container(relay: relay, consent: null);

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop', position: _here);

      final state = container.read(assistantControllerProvider);
      expect(state.problem?.failure, AssistantFailure.consentRequired);
      expect(relay.planCalls, isEmpty);
    });

    test('a refused consent is remembered and keeps refusing', () async {
      final relay = FakeRelayClient();
      final container = await _container(
        relay: relay,
        consent: AiConsent.denied,
      );

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop', position: _here);

      expect(
        container.read(assistantControllerProvider).problem?.failure,
        AssistantFailure.consentRequired,
      );
      expect(relay.planCalls, isEmpty);
    });

    test('a build without a relay says so', () async {
      final container = await _container(
        relay: FakeRelayClient(),
        withRelay: false,
      );

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop', position: _here);

      expect(
        container.read(assistantControllerProvider).problem?.failure,
        AssistantFailure.noRelay,
      );
    });
  });

  group('failures', () {
    test('a rate limit carries its retry-after', () async {
      final relay = FakeRelayClient(
        planFailure: const RelayException(
          RelayError(
            code: RelayErrorCode.rateLimited,
            message: 'too many requests',
            retryAfterS: 90,
          ),
          statusCode: 429,
        ),
      );
      final container = await _container(relay: relay);

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop', position: _here);

      final problem = container.read(assistantControllerProvider).problem!;
      expect(problem.failure, AssistantFailure.rateLimited);
      expect(problem.retryAfterS, 90);
    });

    test('an error event mid-stream fails the request', () async {
      final relay = FakeRelayClient(
        planEvents: const <PlanEvent>[
          ErrorEvent(
            RelayError(
              code: RelayErrorCode.upstreamError,
              message: 'the model is unavailable',
            ),
          ),
        ],
      );
      final container = await _container(relay: relay);

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a loop', position: _here);

      final problem = container.read(assistantControllerProvider).problem!;
      expect(problem.failure, AssistantFailure.relay);
      expect(problem.message, 'the model is unavailable');
    });

    test('a low-confidence answer is questioned, not routed', () async {
      final relay = FakeRelayClient(
        planEvents: <PlanEvent>[
          RouteRequestEvent(
            routeRequest(confidence: 0.2, notes: 'Which lake did you mean?'),
          ),
          const DoneEvent(),
        ],
      );
      final container = await _container(relay: relay);

      await container
          .read(assistantControllerProvider.notifier)
          .submit('something nice', position: _here);

      final problem = container.read(assistantControllerProvider).problem!;
      expect(problem.failure, AssistantFailure.lowConfidence);
      expect(problem.notes, 'Which lake did you mean?');
      expect(container.read(smartLoopControllerProvider).request, isNull);
    });

    test('clearProblem keeps the prompt for another try', () async {
      final relay = FakeRelayClient(planEvents: const <PlanEvent>[DoneEvent()]);
      final container = await _container(relay: relay);
      final controller = container.read(assistantControllerProvider.notifier);

      await controller.submit('a loop', position: _here);
      expect(
        container.read(assistantControllerProvider).problem?.failure,
        AssistantFailure.relay,
      );

      controller.clearProblem();
      final state = container.read(assistantControllerProvider);
      expect(state.problem, isNull);
      expect(state.prompt, 'a loop');
    });
  });
}
