import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';

import 'support/fixtures.dart';

/// Scripted [IncomingSources]: nothing here touches a plugin.
class _FakeSources implements IncomingSources {
  _FakeSources({
    this.initialMedia = const <SharedMediaFile>[],
    this.launchLink,
    Map<String, Uint8List>? files,
    Map<String, Uint8List>? contentUris,
  }) : files = files ?? <String, Uint8List>{},
       contentUris = contentUris ?? <String, Uint8List>{};

  final List<SharedMediaFile> initialMedia;
  final Uri? launchLink;
  final Map<String, Uint8List> files;
  final Map<String, Uint8List> contentUris;

  final StreamController<List<SharedMediaFile>> media =
      StreamController<List<SharedMediaFile>>.broadcast();
  final StreamController<Uri> links = StreamController<Uri>.broadcast();
  final StreamController<String> opened = StreamController<String>.broadcast();

  /// Every path [readFile] was asked for, in order.
  final List<String> readPaths = <String>[];

  /// Every URI [readContentUri] was asked for, in order.
  final List<Uri> readUris = <Uri>[];

  @override
  Future<List<SharedMediaFile>> initialSharedMedia() async => initialMedia;

  @override
  Stream<List<SharedMediaFile>> sharedMediaStream() => media.stream;

  @override
  Future<Uri?> initialLink() async => launchLink;

  @override
  Stream<Uri> linkStream() => links.stream;

  @override
  Stream<String> openedFilePaths() => opened.stream;

  @override
  Future<Uint8List?> readFile(String path) async {
    readPaths.add(path);
    return files[path];
  }

  @override
  Future<Uint8List?> readContentUri(Uri uri) async {
    readUris.add(uri);
    return contentUris[uri.toString()];
  }

  Future<void> close() async {
    await media.close();
    await links.close();
    await opened.close();
  }
}

SharedMediaFile _shared(String path) =>
    SharedMediaFile(path: path, type: SharedMediaType.file);

void main() {
  late Uint8List komoot;
  late Uint8List route;

  setUpAll(() {
    komoot = fixtureBytes('komoot.gpx');
    route = fixtureBytes('route.gpx');
  });

  /// Starts a service over [sources] and collects what it emits.
  Future<(IncomingFileService, List<ImportCandidate>, List<Uri>)> start(
    _FakeSources sources,
  ) async {
    final service = IncomingFileService(sources);
    final imports = <ImportCandidate>[];
    final deepLinks = <Uri>[];
    service.imports.listen(imports.add);
    service.deepLinks.listen(deepLinks.add);
    addTearDown(() async {
      await service.dispose();
      await sources.close();
    });
    await service.start();
    return (service, imports, deepLinks);
  }

  test('a file shared at launch is decoded and emitted', () async {
    final sources = _FakeSources(
      initialMedia: [_shared('/tmp/Feierabend.gpx')],
      files: {'/tmp/Feierabend.gpx': komoot},
    );
    final (_, imports, _) = await start(sources);
    await pumpEventQueue();

    expect(imports, hasLength(1));
    expect(imports.single.fileName, 'Feierabend.gpx');
    expect(imports.single.sourceHint, 'share');
    expect(imports.single.suggested, ImportKind.ride);
  });

  test('a file:// launch link is read from disk', () async {
    final sources = _FakeSources(
      launchLink: Uri.file('/downloads/route.gpx'),
      files: {'/downloads/route.gpx': route},
    );
    final (_, imports, deepLinks) = await start(sources);
    await pumpEventQueue();

    expect(sources.readPaths, ['/downloads/route.gpx']);
    expect(imports.single.suggested, ImportKind.route);
    expect(deepLinks, isEmpty);
  });

  test('a content:// link goes through the platform resolver', () async {
    const uri = 'content://com.android.providers.downloads/document/Tour.gpx';
    final sources = _FakeSources(contentUris: {uri: komoot});
    final (_, imports, _) = await start(sources);

    sources.links.add(Uri.parse(uri));
    await pumpEventQueue();

    expect(sources.readUris.single.toString(), uri);
    expect(sources.readPaths, isEmpty);
    expect(imports.single.fileName, 'Tour.gpx');
    expect(imports.single.sourceHint, 'open');
  });

  test('a velorki:// link is not a file and goes to deepLinks', () async {
    final sources = _FakeSources();
    final (_, imports, deepLinks) = await start(sources);

    sources.links.add(Uri.parse('velorki://oauth/strava?code=abc'));
    await pumpEventQueue();

    expect(imports, isEmpty);
    expect(deepLinks.single.toString(), 'velorki://oauth/strava?code=abc');
    expect(sources.readUris, isEmpty);
  });

  test('the iOS file channel feeds the same pipeline', () async {
    final sources = _FakeSources(files: {'/tmp/incoming/x.gpx': komoot});
    final (_, imports, _) = await start(sources);

    sources.opened.add('/tmp/incoming/x.gpx');
    await pumpEventQueue();

    expect(imports.single.fileName, 'x.gpx');
  });

  test('a file that is not a track is dropped, not thrown', () async {
    final sources = _FakeSources(
      files: {'/tmp/photo.jpg': fixtureBytes('not_gpx.xml')},
    );
    final (_, imports, _) = await start(sources);

    sources.media.add([_shared('/tmp/photo.jpg')]);
    await pumpEventQueue();

    expect(imports, isEmpty);
  });

  test('an unreadable file is dropped, not thrown', () async {
    final sources = _FakeSources();
    final (_, imports, _) = await start(sources);

    sources.opened.add('/nowhere/at/all.gpx');
    await pumpEventQueue();

    expect(sources.readPaths, ['/nowhere/at/all.gpx']);
    expect(imports, isEmpty);
  });

  test('shared plain text is ignored without a read attempt', () async {
    final sources = _FakeSources();
    final (_, imports, _) = await start(sources);

    sources.media.add([
      SharedMediaFile(path: 'just some text', type: SharedMediaType.text),
    ]);
    await pumpEventQueue();

    expect(sources.readPaths, isEmpty);
    expect(imports, isEmpty);
  });

  test('bytes handed in directly skip the platform entirely', () async {
    final sources = _FakeSources();
    final (service, imports, _) = await start(sources);

    await service.addBytes(route, fileName: 'picked.gpx', sourceHint: 'picker');
    await pumpEventQueue();

    expect(imports.single.sourceHint, 'picker');
    expect(sources.readPaths, isEmpty);
    expect(sources.readUris, isEmpty);
  });

  test('start() is idempotent', () async {
    final sources = _FakeSources(
      initialMedia: [_shared('/tmp/a.gpx')],
      files: {'/tmp/a.gpx': komoot},
    );
    final (service, imports, _) = await start(sources);
    await service.start();
    await pumpEventQueue();

    expect(imports, hasLength(1));
  });

  test('the real sources read a real file from disk', () async {
    final sources = PlatformIncomingSources();
    final file = File(fixturePath('route.gpx'));
    expect(await sources.readFile(file.absolute.path), isNotNull);
    expect(await sources.readFile('/definitely/not/here.gpx'), isNull);
  });
}
