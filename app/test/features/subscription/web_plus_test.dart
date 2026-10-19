import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/plus/app_user_id.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/subscription/application/web_plus.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../support/openapi_schema.dart';

/// `POST /plus/web` as the yaml documents it: the named examples of each
/// status, answered in turn.
Map<String, Object?> _examples(OpenApi spec, String status) {
  final op =
      ((spec.document['paths']! as Map)['/plus/web']! as Map)['post']! as Map;
  final content =
      ((op['responses']! as Map)[status]! as Map)['content']! as Map;
  return ((content['application/json']! as Map)['examples']! as Map)
      .cast<String, Object?>();
}

Object? _value(Map<String, Object?> examples, String name) =>
    (examples[name]! as Map)['value'];

void main() {
  final spec = OpenApi.load();

  /// A relay answering [body] with [status], recording the requests.
  ({RelayClient client, List<http.Request> requests}) relay(
    int status,
    Object? body,
  ) {
    final requests = <http.Request>[];
    final client = RelayClient(
      'https://api.velorki.test',
      appUserId: 'anon-browser',
      client: MockClient((request) async {
        requests.add(request);
        expect(
          spec.check(
            'PlusWebRequest',
            jsonDecode(request.body) as Map<String, Object?>,
          ),
          isEmpty,
        );
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (client: client, requests: requests);
  }

  ProviderContainer container(RelayClient client) {
    final c = ProviderContainer(
      overrides: [relayClientProvider.overrideWithValue(client)],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// The yaml's 200 example, with an expiry an hour from now.
  Map<String, Object?> granted() => {
    ...(_value(_examples(spec, '200'), 'granted')! as Map)
        .cast<String, Object?>(),
    'expires_at':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
  };

  test('the documented answers parse in the client and fit the schemas', () {
    for (final MapEntry(:key, :value) in _examples(spec, '200').entries) {
      final body = ((value! as Map)['value']! as Map).cast<String, Object?>();
      expect(spec.check('PlusWebToken', body), isEmpty, reason: key);
      final token = PlusWebToken.fromJson(body);
      expect(token.token, startsWith('vpt1.'));
    }
    for (final MapEntry(:key, :value) in _examples(spec, '403').entries) {
      final body = (value! as Map)['value'];
      expect(spec.check('PlusWebRefusal', body), isEmpty, reason: key);
      expect(RelayError.fromBody(body).reason, isNotNull, reason: key);
    }
  });

  test(
    'a sign-in with Plus holds the token in memory and opens Plus',
    () async {
      final r = relay(200, granted());
      final c = container(r.client);
      expect(c.read(plusEntitledProvider), isFalse);

      final plus = await c
          .read(webPlusProvider.notifier)
          .signIn(PlusWebService.google, 'ya29.cloud');

      expect(c.read(webPlusProvider), same(plus));
      expect(c.read(plusEntitledProvider), isTrue);
      final sent = r.requests.single;
      expect(sent.url.path, '/plus/web');
      expect(jsonDecode(sent.body), {
        'service': 'google',
        'token': 'ya29.cloud',
      });
      expect(sent.headers['Authorization'], isNull, reason: 'no id of its own');

      c.read(webPlusProvider.notifier).forget();
      expect(c.read(webPlusProvider), isNull);
      expect(c.read(plusEntitledProvider), isFalse);
    },
  );

  test('a refusal says why and holds nothing', () async {
    final r = relay(403, _value(_examples(spec, '403'), 'noDevices'));
    final c = container(r.client);
    await expectLater(
      c
          .read(webPlusProvider.notifier)
          .signIn(PlusWebService.icloud, 'ck-token'),
      throwsA(
        isA<RelayException>().having(
          (e) => e.error.reason,
          'reason',
          'no_devices',
        ),
      ),
    );
    expect(c.read(webPlusProvider), isNull);
    expect(c.read(plusEntitledProvider), isFalse);
  });

  test('a token already expired is not held', () async {
    final r = relay(200, {...granted(), 'expires_at': 1000});
    final c = container(r.client);
    await c
        .read(webPlusProvider.notifier)
        .signIn(PlusWebService.google, 'ya29.cloud');
    expect(c.read(webPlusProvider), isNull);
    expect(c.read(plusEntitledProvider), isFalse);
  });

  test('the relay client sends the Plus token held, else the app id', () async {
    SharedPreferences.setMockInitialValues({appUserIdPrefsKey: 'anon-web'});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        effectiveConfigProvider.overrideWithValue(
          const AppConfig(apiUrl: 'https://api.velorki.test'),
        ),
        webPlusProvider.overrideWith(_Held.new),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(relayClientProvider)!.appUserId, 'vpt1.held.mac');
    c.read(webPlusProvider.notifier).forget();
    expect(c.read(relayClientProvider)!.appUserId, 'anon-web');
  });
}

class _Held extends WebPlus {
  @override
  PlusWebToken? build() => PlusWebToken(
    token: 'vpt1.held.mac',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
}
