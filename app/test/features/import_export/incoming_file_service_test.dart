import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki/core/links/location_link.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/import_export/data/track_decoder.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';

import 'support/fixtures.dart';

/// Scripted [IncomingSources]: nothing here touches a plugin.
class _FakeSources implements IncomingSources {
  _FakeSources({
    this.initialMedia = const <SharedMediaFile>[],
    this.launchLink,
    this.initialMediaError,
    this.initialLinkError,
    Map<String, Uint8List>? files,
    Map<String, Uint8List>? contentUris,
  }) : files = files ?? <String, Uint8List>{},
       contentUris = contentUris ?? <String, Uint8List>{};

  final List<SharedMediaFile> initialMedia;
  final Uri? launchLink;

  /// Thrown by [initialSharedMedia] instead of answering, when set.
  final Object? initialMediaError;

  /// Thrown by [initialLink] instead of answering, when set.
  final Object? initialLinkError;
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
  Future<List<SharedMediaFile>> initialSharedMedia() async {
    if (initialMediaError != null) throw initialMediaError!;
    return initialMedia;
  }

  @override
  Stream<List<SharedMediaFile>> sharedMediaStream() => media.stream;

  @override
  Future<Uri?> initialLink() async {
    if (initialLinkError != null) throw initialLinkError!;
    return launchLink;
  }

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List komoot;
  late Uint8List route;

  setUpAll(() {
    komoot = fixtureBytes('komoot.gpx');
    route = fixtureBytes('route.gpx');
  });

  final rejections = <ImportException>[];
  setUp(rejections.clear);

  /// Starts a service over [sources] and collects what it emits.
  Future<(IncomingFileService, List<ImportCandidate>, List<Uri>)> start(
    _FakeSources sources,
  ) async {
    final service = IncomingFileService(sources);
    final imports = <ImportCandidate>[];
    final deepLinks = <Uri>[];
    service.imports.listen(imports.add);
    service.rejections.listen(rejections.add);
    service.deepLinks.listen(deepLinks.add);
    addTearDown(() async {
      await service.dispose();
      await sources.close();
    });
    await service.start();
    return (service, imports, deepLinks);
  }

  test('a file handed over as a file URL is read as a path', () async {
    final sources = _FakeSources(files: {'/tmp/Feier abend.gpx': komoot});
    final (service, imports, _) = await start(sources);

    await service.handlePath(
      'file:///tmp/Feier%20abend.gpx',
      sourceHint: 'share',
    );
    await pumpEventQueue();

    expect(imports.single.fileName, 'Feier abend.gpx');
    expect(sources.readPaths, <String>['/tmp/Feier abend.gpx']);
  });

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
    expect(rejections, hasLength(1));
    expect(rejections.single.failure, ImportFailure.unknownFormat);
    expect(rejections.single.fileName, 'photo.jpg');
  });

  test('an unreadable file is dropped, not thrown', () async {
    final sources = _FakeSources();
    final (_, imports, _) = await start(sources);

    sources.opened.add('/nowhere/at/all.gpx');
    await pumpEventQueue();

    expect(sources.readPaths, ['/nowhere/at/all.gpx']);
    expect(imports, isEmpty);
  });

  test('shared plain text is no file and no read attempt', () async {
    final sources = _FakeSources();
    final (service, imports, deepLinks) = await start(sources);
    final locations = <LocationLink>[];
    service.locations.listen(locations.add);

    sources.media.add([
      SharedMediaFile(path: 'just some text', type: SharedMediaType.text),
    ]);
    await pumpEventQueue();

    expect(sources.readPaths, isEmpty);
    expect(imports, isEmpty);
    expect(deepLinks, isEmpty);
    // Short text may be a place's name: the search gets it.
    expect(locations.single.query, 'just some text');
  });

  group('places', () {
    Future<(_FakeSources, List<LocationLink>, List<Uri>)> startPlaces() async {
      final sources = _FakeSources();
      final (service, _, deepLinks) = await start(sources);
      final locations = <LocationLink>[];
      service.locations.listen(locations.add);
      return (sources, locations, deepLinks);
    }

    test('a geo: intent is a place, not a deep link', () async {
      final (sources, locations, deepLinks) = await startPlaces();

      sources.links.add(Uri.parse('geo:52.52,13.405?z=17'));
      await pumpEventQueue();

      expect(deepLinks, isEmpty);
      expect(locations.single.position, const LatLng(52.52, 13.405));
    });

    test('a velorki://navigate link is a place', () async {
      final (sources, locations, deepLinks) = await startPlaces();

      sources.links.add(
        Uri.parse('velorki://navigate?lat=52.52&lon=13.405&name=Tor'),
      );
      await pumpEventQueue();

      expect(deepLinks, isEmpty);
      expect(locations.single.name, 'Tor');
    });

    test('a place at launch is not lost', () async {
      final sources = _FakeSources(
        launchLink: Uri.parse('velorki://navigate?q=Berlin'),
      );
      final service = IncomingFileService(sources);
      final locations = <LocationLink>[];
      service.locations.listen(locations.add);
      addTearDown(() async {
        await service.dispose();
        await sources.close();
      });
      await service.start();

      expect(locations.single.query, 'Berlin');
    });

    test('one intent reported by both plugins is one place', () async {
      final (sources, locations, _) = await startPlaces();

      sources.media.add([
        SharedMediaFile(path: 'geo:52.52,13.405', type: SharedMediaType.url),
      ]);
      sources.links.add(Uri.parse('geo:52.52,13.405'));
      await pumpEventQueue();

      expect(locations, hasLength(1));
    });

    test('a shared map link is a place', () async {
      final (sources, locations, deepLinks) = await startPlaces();

      sources.media.add([
        SharedMediaFile(
          path: 'https://www.openstreetmap.org/#map=17/52.52/13.405',
          type: SharedMediaType.url,
        ),
      ]);
      await pumpEventQueue();

      expect(deepLinks, isEmpty);
      expect(locations.single.position, const LatLng(52.52, 13.405));
    });

    test('text and a short link in one share are one place', () async {
      final (sources, locations, deepLinks) = await startPlaces();

      sources.media.add([
        SharedMediaFile(
          path: 'Brandenburger Tor\nPariser Platz, Berlin',
          type: SharedMediaType.text,
        ),
        SharedMediaFile(
          path: 'https://maps.app.goo.gl/AbC',
          type: SharedMediaType.url,
        ),
      ]);
      await pumpEventQueue();

      expect(deepLinks, isEmpty);
      expect(locations, hasLength(1));
      expect(
        locations.single.query,
        'Brandenburger Tor, Pariser Platz, Berlin',
      );
    });

    test('a short link alone says it needs a browser', () async {
      final (sources, locations, _) = await startPlaces();

      sources.media.add([
        SharedMediaFile(
          path: 'https://maps.app.goo.gl/AbC',
          type: SharedMediaType.url,
        ),
      ]);
      await pumpEventQueue();

      expect(locations.single.isUnresolvable, isTrue);
    });

    test('a share link shared with text still goes to deepLinks', () async {
      final (sources, locations, deepLinks) = await startPlaces();

      sources.media.add([
        SharedMediaFile(
          path: 'Look at this route of mine, it is a long one along the river',
          type: SharedMediaType.text,
        ),
        SharedMediaFile(
          path: 'https://velorki.com/s/7Kq2mZ0aTb',
          type: SharedMediaType.url,
        ),
      ]);
      await pumpEventQueue();

      expect(locations, isEmpty);
      expect(deepLinks.single.toString(), 'https://velorki.com/s/7Kq2mZ0aTb');
    });

    test('a text file the plugin reports as text is no place', () async {
      final (sources, locations, deepLinks) = await startPlaces();

      sources.media.add([
        SharedMediaFile(
          path: '/data/user/0/com.orkitec.velorki/cache/tour.gpx',
          type: SharedMediaType.text,
        ),
      ]);
      await pumpEventQueue();

      expect(locations, isEmpty);
      expect(deepLinks, isEmpty);
      expect(sources.readPaths, isEmpty);
    });

    test('a long message is no place', () async {
      final (sources, locations, _) = await startPlaces();

      sources.media.add([
        SharedMediaFile(path: 'blah ' * 80, type: SharedMediaType.text),
      ]);
      await pumpEventQueue();

      expect(locations, isEmpty);
    });
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

  group('a URL shared into the app', () {
    test('a file URL is read from disk like any other file', () async {
      final sources = _FakeSources(files: {'/tmp/Tour.gpx': komoot});
      final (_, imports, deepLinks) = await start(sources);

      sources.media.add([
        SharedMediaFile(
          path: 'file:///tmp/Tour.gpx',
          type: SharedMediaType.url,
        ),
      ]);
      await pumpEventQueue();

      expect(sources.readPaths, ['/tmp/Tour.gpx']);
      expect(imports.single.fileName, 'Tour.gpx');
      expect(deepLinks, isEmpty);
    });

    test('a web link is passed on rather than downloaded', () async {
      final sources = _FakeSources();
      final (_, imports, deepLinks) = await start(sources);

      sources.media.add([
        SharedMediaFile(
          path: 'https://example.test/tour.gpx',
          type: SharedMediaType.url,
        ),
      ]);
      await pumpEventQueue();

      expect(sources.readPaths, isEmpty);
      expect(imports, isEmpty);
      expect(deepLinks.single.toString(), 'https://example.test/tour.gpx');
    });

    test('something shared as a URL that is none is ignored', () async {
      final sources = _FakeSources();
      final (_, imports, deepLinks) = await start(sources);

      sources.media.add([
        SharedMediaFile(path: 'http://[', type: SharedMediaType.url),
      ]);
      await pumpEventQueue();

      expect(imports, isEmpty);
      expect(deepLinks, isEmpty);
      expect(sources.readPaths, isEmpty);
    });

    test('a photo shared by accident is read and then dropped', () async {
      final sources = _FakeSources(
        files: {'/tmp/photo.jpg': fixtureBytes('not_gpx.xml')},
      );
      final (_, imports, _) = await start(sources);

      sources.media.add([
        SharedMediaFile(path: '/tmp/photo.jpg', type: SharedMediaType.image),
      ]);
      await pumpEventQueue();

      expect(sources.readPaths, ['/tmp/photo.jpg']);
      expect(imports, isEmpty);
    });
  });

  group('a source that fails', () {
    test('an error on the share stream does not stop the next file', () async {
      final sources = _FakeSources(files: {'/tmp/a.gpx': komoot});
      final (_, imports, _) = await start(sources);

      sources.media.addError(StateError('the share sheet broke'));
      await pumpEventQueue();
      sources.media.add([_shared('/tmp/a.gpx')]);
      await pumpEventQueue();

      expect(imports, hasLength(1));
    });

    test('an error on the link stream does not stop the next link', () async {
      final sources = _FakeSources();
      final (_, _, deepLinks) = await start(sources);

      sources.links.addError(StateError('app_links broke'));
      await pumpEventQueue();
      sources.links.add(Uri.parse('velorki://share/abc'));
      await pumpEventQueue();

      expect(deepLinks.single.toString(), 'velorki://share/abc');
    });

    test('an error on the file channel does not stop the next file', () async {
      final sources = _FakeSources(files: {'/tmp/a.gpx': komoot});
      final (_, imports, _) = await start(sources);

      sources.opened.addError(StateError('the channel broke'));
      await pumpEventQueue();
      sources.opened.add('/tmp/a.gpx');
      await pumpEventQueue();

      expect(imports, hasLength(1));
    });

    test('a plugin that fails at launch does not stop the app', () async {
      final sources = _FakeSources(
        initialMediaError: StateError('no share sheet'),
        initialLinkError: StateError('no links'),
        files: {'/tmp/a.gpx': komoot},
      );

      final (_, imports, _) = await start(sources);
      sources.opened.add('/tmp/a.gpx');
      await pumpEventQueue();

      expect(imports, hasLength(1));
    });
  });

  group('naming the incoming file', () {
    test(
      'a percent-encoded content URI keeps the name the rider sees',
      () async {
        const uri = 'content://downloads/document/Isar%20loop.gpx';
        final sources = _FakeSources(contentUris: {uri: komoot});
        final (_, imports, _) = await start(sources);

        sources.links.add(Uri.parse(uri));
        await pumpEventQueue();

        expect(imports.single.fileName, 'Isar loop.gpx');
      },
    );

    test('a URI without a path is called import', () async {
      const uri = 'content://downloads';
      final sources = _FakeSources(contentUris: {uri: komoot});
      final (_, imports, _) = await start(sources);

      sources.links.add(Uri.parse(uri));
      await pumpEventQueue();

      expect(imports.single.fileName, 'import');
    });

    test('a Windows-style path keeps only its last segment', () async {
      final sources = _FakeSources(
        files: {r'C:\Users\steffen\Downloads\Tour.gpx': komoot},
      );
      final (service, imports, _) = await start(sources);

      await service.handlePath(r'C:\Users\steffen\Downloads\Tour.gpx');
      await pumpEventQueue();

      expect(imports.single.fileName, 'Tour.gpx');
    });

    test('a path that ends in a separator is called import', () async {
      final sources = _FakeSources(files: {'/tmp/incoming/': komoot});
      final (service, imports, _) = await start(sources);

      await service.handlePath('/tmp/incoming/');
      await pumpEventQueue();

      expect(imports.single.fileName, 'import');
    });

    test('an empty file is dropped like an unreadable one', () async {
      final sources = _FakeSources(files: {'/tmp/empty.gpx': Uint8List(0)});
      final (_, imports, _) = await start(sources);

      sources.opened.add('/tmp/empty.gpx');
      await pumpEventQueue();

      expect(imports, isEmpty);
    });
  });

  group('after the service is disposed', () {
    test('nothing more is emitted and the sources are let go', () async {
      final sources = _FakeSources(files: {'/tmp/a.gpx': komoot});
      final (service, imports, deepLinks) = await start(sources);

      await service.dispose();
      sources.opened.add('/tmp/a.gpx');
      sources.links.add(Uri.parse('velorki://share/abc'));
      await service.addBytes(route, fileName: 'late.gpx');
      await pumpEventQueue();

      expect(imports, isEmpty);
      expect(deepLinks, isEmpty);
      expect(sources.readPaths, isEmpty);
    });
  });

  group('the service the app runs on', () {
    test(
      'one service serves the whole process and feeds both streams',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final service = container.read(incomingFileServiceProvider);

        expect(container.read(incomingFileServiceProvider), same(service));
        expect(
          container.read(incomingImportsProvider),
          isA<AsyncValue<ImportCandidate>>(),
        );
        expect(
          container.read(incomingDeepLinksProvider),
          isA<AsyncValue<Uri>>(),
        );
      },
    );
  });

  group('the platform sources', () {
    const channel = MethodChannel(filesChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void answerWith(Future<Object?> Function(MethodCall call) handler) {
      messenger.setMockMethodCallHandler(channel, handler);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    Future<void> pushOpened(Object? argument) =>
        messenger.handlePlatformMessage(
          filesChannelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(openedFileMethod, argument),
          ),
          (_) {},
        );

    test('files opened before the app listened are collected on listen, '
        'then pushes arrive as they come', () async {
      final calls = <MethodCall>[];
      answerWith((call) async {
        calls.add(call);
        return call.method == takePendingMethod
            ? <Object?>['/tmp/incoming/Cold.gpx']
            : null;
      });
      final sources = PlatformIncomingSources(channel: channel);
      final paths = <String>[];
      final subscription = sources.openedFilePaths().listen(paths.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(calls.map((c) => c.method), contains(takePendingMethod));
      expect(paths, <String>['/tmp/incoming/Cold.gpx']);

      await pushOpened('/tmp/incoming/Warm.gpx');
      await pumpEventQueue();
      expect(paths, <String>[
        '/tmp/incoming/Cold.gpx',
        '/tmp/incoming/Warm.gpx',
      ]);
    });

    test('a platform without pending files to collect is left alone', () async {
      answerWith((call) async => throw MissingPluginException());
      final sources = PlatformIncomingSources(channel: channel);
      final paths = <String>[];
      final subscription = sources.openedFilePaths().listen(paths.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(paths, isEmpty);
    });

    test('a content URI is read through the platform resolver', () async {
      final calls = <MethodCall>[];
      answerWith((call) async {
        calls.add(call);
        return Uint8List.fromList(komoot);
      });
      final sources = PlatformIncomingSources(channel: channel);

      final bytes = await sources.readContentUri(
        Uri.parse('content://downloads/document/Tour.gpx'),
      );

      expect(bytes, komoot);
      expect(calls.single.method, openInputStreamMethod);
      expect(calls.single.arguments, 'content://downloads/document/Tour.gpx');
    });

    test('a content URI the platform refuses reads as nothing', () async {
      answerWith((call) async => throw PlatformException(code: 'denied'));
      final sources = PlatformIncomingSources(channel: channel);

      expect(
        await sources.readContentUri(Uri.parse('content://downloads/x.gpx')),
        isNull,
      );
    });

    test('a platform without a content resolver reads as nothing', () async {
      final sources = PlatformIncomingSources(channel: channel);

      expect(
        await sources.readContentUri(Uri.parse('content://downloads/x.gpx')),
        isNull,
      );
    });

    test('a file the platform opened arrives on the stream', () async {
      final sources = PlatformIncomingSources(channel: channel);
      final paths = <String>[];
      final subscription = sources.openedFilePaths().listen(paths.add);
      addTearDown(subscription.cancel);

      await pushOpened('/tmp/incoming/Tour.gpx');

      expect(paths, <String>['/tmp/incoming/Tour.gpx']);
    });

    test(
      'asking twice does not replace the stream already listened to',
      () async {
        final sources = PlatformIncomingSources(channel: channel);
        final first = <String>[];
        final second = <String>[];
        final a = sources.openedFilePaths().listen(first.add);
        final b = sources.openedFilePaths().listen(second.add);
        addTearDown(() async {
          await a.cancel();
          await b.cancel();
        });

        await pushOpened('/tmp/incoming/Tour.gpx');

        expect(first, <String>['/tmp/incoming/Tour.gpx']);
        expect(second, <String>['/tmp/incoming/Tour.gpx']);
      },
    );

    test('an empty or missing path is not a file that was opened', () async {
      final sources = PlatformIncomingSources(channel: channel);
      final paths = <String>[];
      final subscription = sources.openedFilePaths().listen(paths.add);
      addTearDown(subscription.cancel);

      await pushOpened('');
      await pushOpened(null);
      await pushOpened(42);

      expect(paths, isEmpty);
    });

    test('another method on the channel is none of its business', () async {
      final sources = PlatformIncomingSources(channel: channel);
      final paths = <String>[];
      final subscription = sources.openedFilePaths().listen(paths.add);
      addTearDown(subscription.cancel);

      await messenger.handlePlatformMessage(
        filesChannelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('somethingElse', '/tmp/x.gpx'),
        ),
        (_) {},
      );

      expect(paths, isEmpty);
    });
  });
}
