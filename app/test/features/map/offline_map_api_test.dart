import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// The global method channel maplibre_gl's top-level offline functions use.
const MethodChannel _globalChannel = MethodChannel(
  'plugins.flutter.io/maplibre_gl',
);

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

/// The plugin's native side, answering from Dart.
///
/// [MaplibreOfflineMapApi] is the one place that talks to maplibre_gl
/// directly, so serving the channel the plugin speaks is the only way to see
/// what it actually sends and how it reads the answers back.
class FakeMaplibreNative {
  /// Every call the plugin made on the global channel, in order.
  final List<MethodCall> calls = <MethodCall>[];

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

  MockStreamHandlerEventSink? _events;

  /// Answers the global channel until the test ends.
  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_globalChannel, (call) async {
      calls.add(call);
      final args = call.arguments is Map
          ? Map<String, Object?>.from(call.arguments as Map)
          : const <String, Object?>{};
      switch (call.method) {
        case 'downloadOfflineRegion#setup':
          // The plugin subscribes to this event channel next, so the handler
          // has to be in place before this call answers.
          messenger.setMockStreamHandler(
            EventChannel(args['channelName']! as String),
            MockStreamHandler.inline(onListen: (_, events) => _events = events),
          );
          return null;
        case 'downloadOfflineRegion':
          return json.encode(<String, Object?>{
            'id': regionId,
            'definition': args['definition'],
            'metadata': args['metadata'],
          });
        case 'getOfflineRegionStatus':
          final status = this.status;
          if (status == null) {
            throw PlatformException(
              code: 'REGION_GONE',
              message: 'no such region',
            );
          }
          return json.encode(status);
        case 'getListOfRegions':
          return json.encode(listedIds.map(_regionJson).toList());
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_globalChannel, null));
  }

  /// Reports [percent] percent done, with [bytes] written so far.
  void emitProgress(double percent, {int bytes = 0}) => _events!.success(
    json.encode(<String, Object?>{
      'status': 'progress',
      'progress': percent,
      'completedResourceCount': 1,
      'requiredResourceCount': 2,
      'completedResourceSize': bytes,
    }),
  );

  /// Reports the download as finished.
  void emitSuccess() =>
      _events!.success(json.encode(<String, Object?>{'status': 'success'}));

  /// Reports the download as failed.
  void emitError({required String code, String? message}) =>
      _events!.error(code: code, message: message);

  /// The arguments of the last call to [method].
  Map<String, Object?> argumentsOf(String method) => Map<String, Object?>.from(
    calls.lastWhere((c) => c.method == method).arguments as Map,
  );
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
      native.emitSuccess();
      await pending;

      final definition = Map<String, Object?>.from(
        native.argumentsOf('downloadOfflineRegion')['definition']! as Map,
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
      expect(native.argumentsOf('downloadOfflineRegion')['metadata'], {
        'name': 'Zurich',
      });
    },
  );

  test('progress arrives as a fraction of one with the bytes so far', () async {
    final seen = <OfflineDownloadProgress>[];

    final pending = api.download(_spec, onProgress: seen.add);
    await pumpEventQueue();
    native.emitProgress(0, bytes: 0);
    native.emitProgress(40, bytes: 512);
    native.emitProgress(100, bytes: 2048);
    await pumpEventQueue();
    native.emitSuccess();
    await pending;

    expect(seen.map((p) => p.fraction), [0.0, 0.4, 1.0]);
    expect(seen.map((p) => p.completedBytes), [0, 512, 2048]);
  });

  test('a percentage beyond the end is clamped to a full bar', () async {
    final seen = <OfflineDownloadProgress>[];

    final pending = api.download(_spec, onProgress: seen.add);
    await pumpEventQueue();
    native.emitProgress(140, bytes: 2048);
    await pumpEventQueue();
    native.emitSuccess();
    await pending;

    expect(seen.single.fraction, 1.0);
  });

  test('the size of a finished region is the one MapLibre reports', () async {
    native.regionId = 7;

    final pending = api.download(_spec);
    await pumpEventQueue();
    native.emitProgress(50, bytes: 512);
    await pumpEventQueue();
    native.emitSuccess();
    final result = await pending;

    expect(result.maplibreRegionId, 7);
    // 9999 from the status, not the 512 the last progress event mentioned.
    expect(result.sizeBytes, 9999);
    expect(native.argumentsOf('getOfflineRegionStatus')['id'], 7);
  });

  test('an unreadable status leaves the last progress size standing', () async {
    native.status = null;

    final pending = api.download(_spec);
    await pumpEventQueue();
    native.emitProgress(50, bytes: 512);
    await pumpEventQueue();
    native.emitSuccess();
    final result = await pending;

    expect(result.sizeBytes, 512);
  });

  test('a failed download is raised with the cause MapLibre gave', () async {
    final pending = api.download(_spec);
    await pumpEventQueue();
    native.emitError(code: 'NO_SPACE', message: 'no space left on device');

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
    native.emitError(code: 'UNKNOWN');

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
    expect(native.argumentsOf('deleteOfflineRegion')['id'], 11);
  });

  test('the live region ids are the ones MapLibre lists', () async {
    native.listedIds = <int>[3, 9];

    expect(await api.regionIds(), [3, 9]);
  });
}
