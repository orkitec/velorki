import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/data/photon_client.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fake_http.dart';

void main() {
  late FakeHttpAdapter adapter;
  late PhotonClient client;

  setUp(() {
    adapter = FakeHttpAdapter(body: photonFixture);
    client = PhotonClient('https://photon.example.org/', dio: fakeDio(adapter));
  });

  test('builds the documented URL', () {
    final uri = client.buildUri(
      'munich',
      lang: 'de',
      bias: const LatLng(48.1, 11.5),
    );

    expect(uri.path, '/api');
    expect(uri.host, 'photon.example.org');
    expect(uri.queryParameters, {
      'q': 'munich',
      'limit': '8',
      'lang': 'de',
      'lat': '48.1',
      'lon': '11.5',
    });
  });

  test('leaves out the bias and the language when they are unknown', () {
    final uri = client.buildUri('munich');
    expect(uri.queryParameters.containsKey('lat'), isFalse);
    expect(uri.queryParameters.containsKey('lang'), isFalse);
  });

  test('parses Photon features and skips the unusable ones', () async {
    final results = await client.search('munich', lang: 'en');

    expect(adapter.lastUri.queryParameters['q'], 'munich');
    expect(results, hasLength(2));

    final munich = results.first;
    expect(munich.name, 'Munich');
    expect(munich.position, const LatLng(48.1374, 11.5755));
    expect(munich.state, 'Bavaria');
    expect(munich.country, 'Germany');
    expect(munich.osmKey, 'place');
    expect(munich.osmValue, 'city');
    expect(munich.subtitle, 'Bavaria, Germany');

    final cafe = results.last;
    expect(cafe.city, 'Munich');
    expect(cafe.subtitle, 'Munich, Germany');
  });

  test('an empty feature list is not an error', () async {
    adapter.body = '{"type":"FeatureCollection","features":[]}';
    expect(await client.search('nowhere'), isEmpty);
  });

  test('a body that is not a FeatureCollection throws', () {
    expect(
      () => parsePhotonResponse('{"error":"nope"}'),
      throwsA(isA<SearchException>()),
    );
    expect(
      () => parsePhotonResponse('<html>'),
      throwsA(isA<SearchException>()),
    );
  });

  test('an unreachable server throws a SearchException', () async {
    adapter.failure = DioException.connectionError(
      requestOptions: RequestOptions(),
      reason: 'down',
    );

    await expectLater(client.search('munich'), throwsA(isA<SearchException>()));
  });

  test('a cancelled request keeps its dio exception', () async {
    final token = CancelToken()..cancel();
    await expectLater(
      client.search('munich', cancelToken: token),
      throwsA(isA<DioException>()),
    );
  });
}
