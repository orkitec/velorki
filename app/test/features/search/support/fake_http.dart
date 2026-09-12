import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A dio adapter that answers from a canned body instead of the network.
class FakeHttpAdapter implements HttpClientAdapter {
  /// Answers every request with [body] and [statusCode].
  FakeHttpAdapter({
    this.body = '{"type":"FeatureCollection","features":[]}',
    this.statusCode = 200,
    this.failure,
  });

  /// The body to return.
  String body;

  /// The status to return.
  int statusCode;

  /// When set, the request throws this instead of answering.
  Object? failure;

  /// Every request that arrived, in order.
  final List<Uri> requests = <Uri>[];

  /// The URI of the last request.
  Uri get lastUri => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final error = failure;
    if (error != null) throw error;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A dio wired to [adapter] and nothing else.
Dio fakeDio(FakeHttpAdapter adapter) => Dio()..httpClientAdapter = adapter;

/// A Photon answer with two usable places and two unusable features.
const String photonFixture = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [11.5755, 48.1374] },
      "properties": {
        "osm_id": 240109189,
        "osm_type": "N",
        "osm_key": "place",
        "osm_value": "city",
        "name": "Munich",
        "state": "Bavaria",
        "country": "Germany",
        "countrycode": "DE"
      }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [11.4, 48.0] },
      "properties": {
        "osm_key": "amenity",
        "osm_value": "cafe",
        "name": "Cafe Kosmos",
        "city": "Munich",
        "country": "Germany"
      }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": ["nonsense"] },
      "properties": { "name": "Broken" }
    },
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [9.0, 47.0] },
      "properties": { "osm_key": "highway" }
    }
  ]
}
''';
