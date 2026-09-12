import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// One canned answer of [FakeSegmentsAdapter].
class FakeSegmentsResponse {
  /// A JSON body.
  FakeSegmentsResponse.json(Object? body, {this.status = 200})
    : bytes = Uint8List.fromList(utf8.encode(jsonEncode(body))),
      contentType = 'application/json',
      error = null;

  /// An HTML or text body.
  FakeSegmentsResponse.text(
    String body, {
    this.status = 200,
    this.contentType = 'text/html',
  }) : bytes = Uint8List.fromList(utf8.encode(body)),
       error = null;

  /// A binary body, e.g. a tile.
  FakeSegmentsResponse.bytes(
    this.bytes, {
    this.status = 200,
    this.contentType = 'application/octet-stream',
  }) : error = null;

  /// A transport failure instead of an answer.
  FakeSegmentsResponse.failure(this.error, {this.status = 500})
    : bytes = Uint8List(0),
      contentType = 'text/plain';

  /// The body.
  final Uint8List bytes;

  /// The HTTP status.
  final int status;

  /// The content type header.
  final String contentType;

  /// Thrown instead of answering, when set.
  final Object? error;
}

/// Answers dio requests from a handler instead of the network, with the
/// `Range` support a resumable tile download needs.
class FakeSegmentsAdapter implements HttpClientAdapter {
  /// Creates an adapter driven by [handler].
  FakeSegmentsAdapter(this.handler);

  /// Serves one tile, honouring `Range`, and nothing else.
  factory FakeSegmentsAdapter.serving(
    Uint8List tile, {
    bool supportsRange = true,
  }) => FakeSegmentsAdapter((options) {
    final range = options.headers[HttpHeaders.rangeHeader]?.toString();
    if (!supportsRange || range == null) {
      return FakeSegmentsResponse.bytes(tile);
    }
    final start = int.parse(range.split('=').last.split('-').first);
    return FakeSegmentsResponse.bytes(
      Uint8List.sublistView(tile, start),
      status: 206,
    );
  });

  /// Answers one request.
  final FakeSegmentsResponse Function(RequestOptions options) handler;

  /// Every request that arrived, in order.
  final List<RequestOptions> requests = <RequestOptions>[];

  /// The `Range` headers that were sent, `null` where there was none.
  List<String?> get ranges => <String?>[
    for (final r in requests) r.headers[HttpHeaders.rangeHeader]?.toString(),
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = handler(options);
    final error = response.error;
    if (error != null) throw error;
    return ResponseBody.fromBytes(
      response.bytes,
      response.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[response.contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A dio wired to [adapter] and nothing else.
Dio segmentsDioWith(FakeSegmentsAdapter adapter) =>
    Dio()..httpClientAdapter = adapter;

/// A temporary directory that is removed when the test ends.
Directory tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });
  return dir;
}
