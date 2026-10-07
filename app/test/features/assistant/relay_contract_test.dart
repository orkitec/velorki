// The in-process relay the AI tests talk to is held to web/openapi.yaml, the
// same document the relay's contract tests replay byte for byte against the
// real handler. The examples are Dart copies so they reach a device build;
// this file fails as soon as a copy and the yaml part ways.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../support/mock_relay.dart';
import '../../support/openapi_schema.dart';

/// The frames of a documented stream: (event, data) for each event, null
/// for a comment.
List<(String, Object?)?> _frames(String wire) => [
  for (final block in wire.split('\n\n').where((b) => b.isNotEmpty))
    if (block.startsWith(':'))
      null
    else
      (
        block.split('\n')[0].substring('event: '.length),
        jsonDecode(block.split('\n')[1].substring('data: '.length)),
      ),
];

void main() {
  final spec = OpenApi.load();

  group('the documented streams', () {
    test('are the yaml\'s, every one of them, byte for byte', () {
      final yaml = spec.planStreamExamples;
      expect(documentedPlanStreams.keys, unorderedEquals(yaml.keys));
      for (final name in yaml.keys) {
        expect(
          documentedPlanStreams[name],
          (yaml[name]! as Map<String, Object?>)['value'],
          reason: 'the "$name" example',
        );
      }
    });

    test('come out of the mock\'s framing byte for byte', () {
      for (final name in documentedPlanStreams.keys) {
        final rebuilt = [
          for (final frame in _frames(onTheWire(name)))
            frame == null
                ? SseFrame.open.wire
                : SseFrame.event(frame.$1, frame.$2).wire,
        ].join();
        expect(rebuilt, onTheWire(name), reason: 'the "$name" example');
      }
    });

    test('carry payloads the schemas accept', () {
      const schemaOf = {
        'route_request': 'ProposeRoute',
        'route_advice': 'RouteAdvice',
        'error': 'Error',
      };
      var checked = 0;
      for (final name in documentedPlanStreams.keys) {
        for (final frame in _frames(onTheWire(name)).nonNulls) {
          final schema = schemaOf[frame.$1];
          if (schema == null) continue;
          expect(spec.check(schema, frame.$2), isEmpty, reason: name);
          checked++;
        }
      }
      expect(checked, 3);
    });

    test('parse in the app\'s client into what each step expects', () async {
      final relay = MockRelay(schemas: spec.check);
      final client = relay.client();
      addTearDown(client.close);
      final summary = RouteSummary(
        distanceKm: 10,
        ascentM: 100,
        surface: const SurfaceMix(paved: 1),
        digest: const RouteDigest(loop: false),
      );
      Future<List<PlanEvent>> run(String step) => client
          .planStream(
            step: step,
            prompt: 'x',
            routeSummary: step == 'plan' ? null : summary,
          )
          .toList();

      expect((await run('plan')).first, isA<RouteRequestEvent>());
      expect(
        (await run('describe')).first,
        const TextEvent('Diese Runde führt '),
      );
      final route = await run('route');
      expect(
        (route.first as RouteAdviceEvent).advice.findings.single.fix,
        const AddStopFix('p1'),
      );
      expect(route.last, isA<DoneEvent>());
      relay.reply(RelayReply.documented('failure'));
      final failure = await run('plan');
      expect(
        (failure.single as ErrorEvent).error.code,
        RelayErrorCode.invalidRequest,
      );
    });
  });

  group('the documented errors', () {
    test('are the yaml\'s, under the status /ai/plan lists them at', () {
      final responses = spec.aiPlan['responses']! as Map<String, Object?>;
      for (final error in documentedErrors) {
        final listed = responses['${error.status}']! as Map<String, Object?>;
        expect(
          listed[r'$ref'],
          '#/components/responses/${error.component}',
          reason: error.component,
        );
        final examples =
            ((spec.response(error.component)['content']!
                        as Map<String, Object?>)['application/json']!
                    as Map<String, Object?>)['examples']!
                as Map<String, Object?>;
        expect(
          jsonDecode(error.body),
          (examples.values.single! as Map<String, Object?>)['value'],
          reason: error.component,
        );
        expect(spec.check('Error', jsonDecode(error.body)), isEmpty);
      }
      expect(
        (spec.response('RateLimited')['headers']! as Map).keys,
        contains('Retry-After'),
      );
    });

    test('the deadline message is the relay\'s', () {
      final handler = File('../web/src/app/(api)/ai/plan/route.ts')
          .readAsStringSync();
      expect(handler, contains("'$relayDeadlineMessage'"));
    });
  });

  group('the request schema the mock holds the app to', () {
    test('accepts every documented request', () {
      final examples = spec.planRequestExamples;
      expect(examples, isNotEmpty);
      for (final name in examples.keys) {
        final value = (examples[name]! as Map<String, Object?>)['value'];
        expect(spec.check('PlanRequest', value), isEmpty, reason: name);
      }
    });

    test('refuses what the relay refuses', () {
      final route = Map<String, Object?>.from(
        (spec.planRequestExamples['route']! as Map<String, Object?>)['value']!
            as Map<String, Object?>,
      );
      final summary = Map<String, Object?>.from(
        route['route_summary']! as Map<String, Object?>,
      )..remove('digest');
      expect(spec.check('PlanRequest', {...route, 'route_summary': summary}), [
        'PlanRequest.route_summary.digest missing',
      ]);
      expect(spec.check('PlanRequest', {...route, 'position': 1}), [
        'PlanRequest.position not allowed',
      ]);
      expect(spec.check('PlanRequest', {...route, 'prompt': ''}), isNotEmpty);
      expect(
        spec.check('PlanRequest', {...route, 'locale': 'de_DE'}),
        isNotEmpty,
      );
      expect(
        spec.check('PlanRequest', {...route}..remove('route_summary')),
        isNotEmpty,
      );
      expect(
        spec.check('RouteAdvice', {
          'answer': 'x',
          'findings': [
            {
              'kind': 'food',
              'text': 'x',
              'fix': {'type': 'add_stop', 'place_id': 'cafe'},
            },
          ],
        }),
        isNotEmpty,
      );
    });
  });
}
