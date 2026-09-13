import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One canned answer of [FakeApiAdapter].
class FakeResponse {
  /// A JSON answer.
  FakeResponse.json(Object? body, {this.status = 200})
    : body = jsonEncode(body),
      bytes = null,
      contentType = 'application/json';

  /// A text answer, for the GPX exports.
  FakeResponse.text(
    String text, {
    this.status = 200,
    this.contentType = 'application/gpx+xml',
  }) : body = text,
       bytes = Uint8List.fromList(utf8.encode(text));

  /// A raw error body.
  FakeResponse.raw(
    this.body, {
    this.status = 500,
    this.contentType = 'text/html',
  }) : bytes = null;

  /// The body as a string.
  final String body;

  /// The body as bytes, when the caller asked for bytes.
  final Uint8List? bytes;

  /// The HTTP status.
  final int status;

  /// The content type header.
  final String contentType;
}

/// Answers dio requests from a handler instead of the network.
///
/// Records every request so a test can assert the URL, the query and the
/// multipart fields that were sent.
class FakeApiAdapter implements HttpClientAdapter {
  /// Creates an adapter driven by [handler].
  FakeApiAdapter(this.handler);

  /// Answers one request.
  final FakeResponse Function(RequestOptions options) handler;

  /// Every request that arrived, in order.
  final List<RequestOptions> requests = <RequestOptions>[];

  /// The URIs of [requests].
  List<Uri> get uris => <Uri>[for (final r in requests) r.uri];

  /// How often the dio this adapter belongs to was closed.
  ///
  /// `Dio.close` closes its adapter, so a provider that releases its client in
  /// `ref.onDispose` can be proved to have done so.
  int closes = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = handler(options);
    final headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[response.contentType],
    };
    if (options.responseType == ResponseType.bytes) {
      return ResponseBody.fromBytes(
        response.bytes ?? Uint8List.fromList(utf8.encode(response.body)),
        response.status,
        headers: headers,
      );
    }
    return ResponseBody.fromString(
      response.body,
      response.status,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) => closes++;
}

/// A dio wired to [adapter] and nothing else.
Dio dioWith(FakeApiAdapter adapter) => Dio()..httpClientAdapter = adapter;

/// The multipart fields of a recorded request, as a map.
Map<String, String> multipartFields(RequestOptions options) {
  final data = options.data;
  if (data is! FormData) return const <String, String>{};
  return <String, String>{
    for (final entry in data.fields) entry.key: entry.value,
  };
}

/// The multipart file field names of a recorded request.
List<String> multipartFileNames(RequestOptions options) {
  final data = options.data;
  if (data is! FormData) return const <String>[];
  return <String>[for (final entry in data.files) entry.key];
}
