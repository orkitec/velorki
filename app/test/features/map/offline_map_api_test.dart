import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The plugin's Pigeon messages: their codec and the download event native
// sends are what the native side of the plugin speaks, and the plugin keeps
// them under src/ (its own tests import them the same way).
// ignore: implementation_imports
import 'package:maplibre_gl/src/native/messages.g.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// The Pigeon channels maplibre_gl's top-level offline functions call
/// native through, one per method, and the one native sends download events
/// back on.
const String _hostApi = 'dev.flutter.pigeon.maplibre_gl.MapLibreGlobalHostApi';
const String _onDownloadEvent =
    'dev.flutter.pigeon.maplibre_gl.MapLibreOfflineDownloadFlutterApi'
    '.onDownloadEvent';
const MessageCodec<Object?> _codec = MapLibreGlobalHostApi.pigeonChannelCodec;

const String _styleUrl = 'https://tiles.example/style.json';
const BoundingBox _bounds = BoundingBox(
  south: 47.0,
  west: 8.0,
  north: 47.5,
  east: 8.6,
);
const OfflineRegionSpec _spec = OfflineRegionSpec(
  name: 'Zurich',
  bounds: _bounds,
  styleUrl: _styleUrl,
);

/// One region as the plugin's native side describes it.
Map<String, Object?> _regionJson(int id) => <String, Object?>{
  'id': id,
  'definition': <String, Object?>{
    'bounds': <List<double>>[
      <double>[47.0, 8.0],
      <double>[47.5, 8.6],
    ],
    'mapStyleUrl': _styleUrl,
    'minZoom': 6,
    'maxZoom': 15,
    'includeIdeographs': false,
  },
  'metadata': <String, Object?>{'name': 'Zurich'},
};

/// A call native received: the method and its decoded arguments.
typedef NativeCall = ({String method, List<Object?> arguments});

/// The plugin's native side, answering from Dart.
///
/// [MaplibreOfflineMapApi] is the one place that talks to maplibre_gl
/// directly, so serving the channels the plugin speaks, with its codec and
/// the reply envelopes of the generated Kotlin and Swift code (`[result]`,
/// or `[code, message, details]` for an error), is the only way to see what
/// it actually sends and how it reads the answers back.
class FakeMaplibreNative {
  /// Every call the plugin made, in order.
  final List<NativeCall> calls = <NativeCall>[];

  /// The id a started download is given.
  int regionId = 42;

  /// What `getOfflineRegionStatus` answers; `null` makes it fail, as it does
  /// when the offline database has moved on.
  Map<String, Object?>? status = <String, Object?>{
    'completedResourceCount': 120,
    'requiredResourceCount': 120,
    'completedResourceSize': 9999,
    'isComplete': true,
    'downloadProgress': 100,
  };

  /// The ids `getListOfRegions` answers with.
  List<int> listedIds = <int>[];

  /// The id the plugin tagged the last download with; native tags each of
  /// its events with it.
  int? _downloadId;

  static TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  static const List<String> _methods = <String>[
    'downloadOfflineRegion',
    'getOfflineRegionStatus',
    'getListOfRegions',
    'deleteOfflineRegion',
    'clearAmbientCache',
  ];

  /// Answers the plugin's channels until the test ends.
  void install() {
    for (final method in _methods) {
      _messenger.setMockMessageHandler('$_hostApi.$method', (message) async {
        final arguments =
            (_codec.decodeMessage(message) as List<Object?>?) ??
            const <Object?>[];
        calls.add((method: method, arguments: arguments));
        try {
          return _codec.encodeMessage(<Object?>[_answer(method, arguments)]);
        } on PlatformException catch (e) {
          return _codec.encodeMessage(<Object?>[e.code, e.message, e.details]);
        }
      });
      addTearDown(
        () => _messenger.setMockMessageHandler('$_hostApi.$method', null),
      );
    }
  }

  Object? _answer(String method, List<Object?> arguments) {
    switch (method) {
      case 'downloadOfflineRegion':
        _downloadId = arguments[0]! as int;
        return json.encode(<String, Object?>{
          'id': regionId,
          'definition': arguments[1],
          'metadata': arguments[2],
        });
      case 'getOfflineRegionStatus':
        final status = this.status;
        if (status == null) {
          throw PlatformException(
            code: 'REGION_NOT_FOUND',
            message: 'no such region',
          );
        }
        return json.encode(status);
      case 'getListOfRegions':
        return json.encode(listedIds.map(_regionJson).toList());
      default:
        return null;
    }
  }

  Future<void> _emit(PgOfflineDownloadEvent event) async {
    await _messenger.handlePlatformMessage(
      _onDownloadEvent,
      MapLibreOfflineDownloadFlutterApi.pigeonChannelCodec.encodeMessage(
        <Object?>[_downloadId!, event],
      ),
      null,
    );
  }

  /// Reports [percent] percent done, with [bytes] written so far.
  Future<void> emitProgress(double percent, {int bytes = 0}) => _emit(
    PgOfflineDownloadEvent(
      status: PgOfflineDownloadStatus.progress,
      progress: percent,
      completedResourceCount: 1,
      requiredResourceCount: 2,
      completedResourceSize: bytes,
    ),
  );

  /// Reports the download as finished.
  Future<void> emitSuccess() =>
      _emit(PgOfflineDownloadEvent(status: PgOfflineDownloadStatus.success));

  /// Reports the download as failed.
  Future<void> emitError({required String code, String? message}) => _emit(
    PgOfflineDownloadEvent(
      status: PgOfflineDownloadStatus.error,
      errorCode: code,
      errorMessage: message,
    ),
  );

  /// The arguments of the last call to [method].
  List<Object?> argumentsOf(String method) =>
      calls.lastWhere((c) => c.method == method).arguments;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMaplibreNative native;
  const api = MaplibreOfflineMapApi();

  setUp(() {
    native = FakeMaplibreNative()..install();
  });

  test(
    'a download asks for the bounds, the style and the zoom range',
    () async {
      final pending = api.download(_spec);
      await pumpEventQueue();
      await native.emitSuccess();
      await pending;

      final definition = Map<String, Object?>.from(
        native.argumentsOf('downloadOfflineRegion')[1]! as Map,
      );
      // The plugin normalises every longitude it is handed, which costs the
      // last bits of the double; a tenth of a micrometre is not a tile.
      final corners = (definition['bounds']! as List)
          .map((corner) => (corner as List).cast<num>())
          .toList();
      expect(corners[0][0], closeTo(47.0, 1e-9));
      expect(corners[0][1], closeTo(8.0, 1e-9));
      expect(corners[1][0], closeTo(47.5, 1e-9));
      expect(corners[1][1], closeTo(8.6, 1e-9));
      expect(definition['mapStyleUrl'], _styleUrl);
      expect(definition['minZoom'], 6.0);
      expect(definition['maxZoom'], 15.0);
      // The name travels as metadata so a region merged from another device can
      // still be identified.
      expect(native.argumentsOf('downloadOfflineRegion')[2], {
        'name': 'Zurich',
      });
    },
  );

  test('progress arrives as a fraction of one with the bytes so far', () async {
    final seen = <OfflineDownloadProgress>[];

    final pending = api.download(_spec, onProgress: seen.add);
    await pumpEventQueue();
    await native.emitProgress(0, bytes: 0);
    await native.emitProgress(40, bytes: 512);
    await native.emitProgress(100, bytes: 2048);
    await pumpEventQueue();
    await native.emitSuccess();
    await pending;

    expect(seen.map((p) => p.fraction), [0.0, 0.4, 1.0]);
    expect(seen.map((p) => p.completedBytes), [0, 512, 2048]);
  });

  test('a percentage beyond the end is clamped to a full bar', () async {
    final seen = <OfflineDownloadProgress>[];

    final pending = api.download(_spec, onProgress: seen.add);
    await pumpEventQueue();
    await native.emitProgress(140, bytes: 2048);
    await pumpEventQueue();
    await native.emitSuccess();
    await pending;

    expect(seen.single.fraction, 1.0);
  });

  test('the size of a finished region is the one MapLibre reports', () async {
    native.regionId = 7;

    final pending = api.download(_spec);
    await pumpEventQueue();
    await native.emitProgress(50, bytes: 512);
    await pumpEventQueue();
    await native.emitSuccess();
    final result = await pending;

    expect(result.maplibreRegionId, 7);
    // 9999 from the status, not the 512 the last progress event mentioned.
    expect(result.sizeBytes, 9999);
    expect(native.argumentsOf('getOfflineRegionStatus'), [7]);
  });

  test('an unreadable status leaves the last progress size standing', () async {
    native.status = null;

    final pending = api.download(_spec);
    await pumpEventQueue();
    await native.emitProgress(50, bytes: 512);
    await pumpEventQueue();
    await native.emitSuccess();
    final result = await pending;

    expect(result.sizeBytes, 512);
  });

  test('a failed download is raised with the cause MapLibre gave', () async {
    final pending = api.download(_spec);
    await pumpEventQueue();
    await native.emitError(
      code: 'NO_SPACE',
      message: 'no space left on device',
    );

    await expectLater(
      pending,
      throwsA(
        isA<OfflineDownloadException>().having(
          (e) => e.message,
          'message',
          'no space left on device',
        ),
      ),
    );
  });

  test('a failure without a message is raised under its code', () async {
    final pending = api.download(_spec);
    await pumpEventQueue();
    await native.emitError(code: 'UNKNOWN');

    await expectLater(
      pending,
      throwsA(
        isA<OfflineDownloadException>().having(
          (e) => e.message,
          'message',
          'UNKNOWN',
        ),
      ),
    );
  });

  test('deleting a region also drops the tiles it shared', () async {
    await api.delete(11);

    expect(native.calls.map((c) => c.method), [
      'deleteOfflineRegion',
      // Without this "delete" frees almost nothing: the ambient cache keeps
      // every tile the region shared with it.
      'clearAmbientCache',
    ]);
    expect(native.argumentsOf('deleteOfflineRegion'), [11]);
  });

  test('the live region ids are the ones MapLibre lists', () async {
    native.listedIds = <int>[3, 9];

    expect(await api.regionIds(), [3, 9]);
  });

  test('a download that stops making progress is given up and its pack '
      'deleted, so MapLibre stops retrying', () async {
    const impatient = MaplibreOfflineMapApi(
      stallTimeout: Duration(milliseconds: 200),
    );
    final pending = impatient.download(_spec);
    final failed = expectLater(
      pending,
      throwsA(isA<OfflineDownloadException>()),
    );
    await pumpEventQueue();
    await native.emitProgress(30, bytes: 512);

    await failed;
    expect(
      native.calls.where((c) => c.method == 'deleteOfflineRegion'),
      hasLength(1),
    );
  });

  test('progress keeps a slow download alive', () async {
    const impatient = MaplibreOfflineMapApi(
      stallTimeout: Duration(milliseconds: 200),
    );
    final pending = impatient.download(_spec);
    await pumpEventQueue();
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await native.emitProgress(20.0 * i, bytes: 100 * i);
    }
    await native.emitSuccess();
    final result = await pending;
    expect(result.maplibreRegionId, native.regionId);
  });
}
