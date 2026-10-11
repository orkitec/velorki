import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/data/osm_details.dart';
import 'package:velorki/features/search/domain/osm_place_details.dart';

import 'support/fake_http.dart';

const String _cafe = '''
{
  "version": "0.6",
  "elements": [
    {
      "type": "node",
      "id": 1234,
      "lat": 47.14,
      "lon": 9.52,
      "tags": {
        "amenity": "cafe",
        "name": "Café Wolf",
        "opening_hours": "Mo-Fr 08:00-18:00",
        "contact:website": "www.cafe-wolf.example/",
        "phone": "+423 232 00 00; +423 232 00 01",
        "cuisine": "coffee_shop;ice_cream",
        "wheelchair": "limited",
        "outdoor_seating": "yes",
        "wikipedia": "de:Café Wolf (Vaduz)"
      }
    }
  ]
}
''';

void main() {
  late FakeHttpAdapter adapter;
  late OsmDetailsClient client;

  setUp(() {
    adapter = FakeHttpAdapter(body: _cafe);
    client = OsmDetailsClient(dio: fakeDio(adapter));
  });

  test('asks the OSM API for the element', () async {
    await client.tags('node', 1234);
    expect(
      adapter.lastUri.toString(),
      'https://api.openstreetmap.org/api/0.6/node/1234.json',
    );
    expect(
      client.uri('way', 9).toString(),
      'https://api.openstreetmap.org/api/0.6/way/9.json',
    );
  });

  test('reads the tags the card shows', () async {
    final details = OsmPlaceDetails.fromTags(await client.tags('node', 1234));
    expect(details.openingHours, 'Mo-Fr 08:00-18:00');
    expect(details.website, Uri.parse('https://www.cafe-wolf.example/'));
    expect(details.phone, '+423 232 00 00');
    expect(details.phoneUri, Uri.parse('tel:+4232320000'));
    expect(details.cuisines, <String>['coffee shop', 'ice cream']);
    expect(details.wheelchair, WheelchairAccess.limited);
    expect(details.outdoorSeating, isTrue);
    expect(
      details.wikipedia.toString(),
      'https://de.wikipedia.org/wiki/Caf%C3%A9_Wolf_(Vaduz)',
    );
    expect(details.wikipediaTitle, 'Café Wolf (Vaduz)');
    expect(details.isEmpty, isFalse);
  });

  test('an element without those tags has nothing to show', () async {
    adapter.body =
        '{"elements":[{"type":"way","id":5,"tags":{"building":"yes"}}]}';
    expect(
      OsmPlaceDetails.fromTags(await client.tags('way', 5)).isEmpty,
      isTrue,
    );
    adapter.body = '{"elements":[{"type":"node","id":6}]}';
    expect(await client.tags('node', 6), isEmpty);
  });

  test('a deleted or unknown element has nothing to show', () async {
    for (final status in [404, 410]) {
      adapter
        ..statusCode = status
        ..body = '';
      expect(await client.tags('node', status), isEmpty);
    }
  });

  test('a failure throws, and a retry asks again', () async {
    adapter.failure = DioException.connectionError(
      requestOptions: RequestOptions(),
      reason: 'offline',
    );
    await expectLater(
      client.tags('node', 1234),
      throwsA(isA<OsmDetailsException>()),
    );
    adapter.failure = null;
    final tags = await client.tags('node', 1234);
    expect(tags['opening_hours'], isNotNull);
    expect(adapter.requests, hasLength(2));
  });

  test('a server error throws', () async {
    adapter.statusCode = 503;
    await expectLater(
      client.tags('node', 1),
      throwsA(isA<OsmDetailsException>()),
    );
  });

  test('a garbled answer throws', () async {
    adapter.body = '<html>';
    await expectLater(
      client.tags('node', 1),
      throwsA(isA<OsmDetailsException>()),
    );
  });

  group('OsmPlaceDetails.fromTags', () {
    test('only http and https websites', () {
      expect(
        OsmPlaceDetails.fromTags(const {'website': 'ftp://x.example'}).website,
        isNull,
      );
      expect(
        OsmPlaceDetails.fromTags(const {'website': 'http://x.example/a'})
            .website,
        Uri.parse('http://x.example/a'),
      );
    });

    test('a wikipedia tag without a language is left out', () {
      expect(
        OsmPlaceDetails.fromTags(const {'wikipedia': 'Vaduz'}).wikipedia,
        isNull,
      );
    });

    test('wheelchair values', () {
      WheelchairAccess? of(String v) =>
          OsmPlaceDetails.fromTags({'wheelchair': v}).wheelchair;
      expect(of('yes'), WheelchairAccess.yes);
      expect(of('designated'), WheelchairAccess.yes);
      expect(of('no'), WheelchairAccess.no);
      expect(of('unknown'), isNull);
    });
  });
}
