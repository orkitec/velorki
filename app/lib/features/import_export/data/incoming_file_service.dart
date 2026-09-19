import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/imported_track.dart';
import 'track_decoder.dart';

part 'incoming_file_service.g.dart';

/// The channel the Android activity and the iOS app delegate push file opens
/// through, and the one Android reads a `content://` URI over.
const String filesChannelName = 'velorki/files';

/// Method the platform invokes on the app when a file was opened with Velorki.
/// Its argument is the path of a readable copy.
const String openedFileMethod = 'opened';

/// Method the app invokes on Android to read a `content://` URI through the
/// `ContentResolver`. Its argument is the URI string, its result the bytes.
const String openInputStreamMethod = 'openInputStream';

final Logger _log = Logger('IncomingFileService');

/// The platform plumbing [IncomingFileService] sits on.
///
/// Split out as an interface purely for testability: a `flutter test` run has
/// no share sheet, no `content://` resolver and no app delegate, and a widget
/// test that wants to drive an import should not have to mock three plugins.
abstract class IncomingSources {
  /// Files the app was launched with through the share sheet.
  Future<List<SharedMediaFile>> initialSharedMedia();

  /// Files shared into the app while it was already running.
  Stream<List<SharedMediaFile>> sharedMediaStream();

  /// The link the app was launched with, if any.
  Future<Uri?> initialLink();

  /// Links delivered while the app was already running.
  Stream<Uri> linkStream();

  /// Paths pushed over the `velorki/files` channel; this is how iOS reports an
  /// "Open in Velorki" (the share sheet goes through the Share Extension and
  /// `receive_sharing_intent` instead).
  Stream<String> openedFilePaths();

  /// Reads [path] from the file system, or `null` when it cannot be read.
  Future<Uint8List?> readFile(String path);

  /// Reads a `content://` URI through the platform's content resolver, or
  /// `null` when the platform cannot (iOS, or a revoked permission).
  Future<Uint8List?> readContentUri(Uri uri);
}

/// The production [IncomingSources]: `receive_sharing_intent`, `app_links` and
/// the `velorki/files` method channel.
class PlatformIncomingSources implements IncomingSources {
  /// Creates the platform sources.
  PlatformIncomingSources({AppLinks? appLinks, MethodChannel? channel})
    : _appLinks = appLinks ?? AppLinks(),
      _channel = channel ?? const MethodChannel(filesChannelName);

  final AppLinks _appLinks;
  final MethodChannel _channel;
  StreamController<String>? _opened;

  @override
  Future<List<SharedMediaFile>> initialSharedMedia() =>
      ReceiveSharingIntent.instance.getInitialMedia();

  @override
  Stream<List<SharedMediaFile>> sharedMediaStream() =>
      ReceiveSharingIntent.instance.getMediaStream();

  @override
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> linkStream() => _appLinks.uriLinkStream;

  @override
  Stream<String> openedFilePaths() {
    final existing = _opened;
    if (existing != null) return existing.stream;
    final controller = StreamController<String>.broadcast(
      onCancel: () {
        _channel.setMethodCallHandler(null);
      },
    );
    _opened = controller;
    _channel.setMethodCallHandler((call) async {
      if (call.method != openedFileMethod) return null;
      final path = call.arguments;
      if (path is String && path.isNotEmpty) controller.add(path);
      return null;
    });
    return controller.stream;
  }

  @override
  Future<Uint8List?> readFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      _log.warning('cannot read $path', e);
      return null;
    }
  }

  @override
  Future<Uint8List?> readContentUri(Uri uri) async {
    try {
      return await _channel.invokeMethod<Uint8List>(
        openInputStreamMethod,
        uri.toString(),
      );
    } on PlatformException catch (e) {
      _log.warning('cannot read $uri', e);
      return null;
    } on MissingPluginException {
      // iOS has no ContentResolver; a file:// URL is handled above and
      // everything else arrives through the app delegate instead.
      return null;
    }
  }
}

/// Unifies every way a GPX or FIT file can reach the app.
///
/// Three sources feed the same pipeline:
///
/// * the **share sheet** (`receive_sharing_intent`), which already resolves
///   `content://` URIs to readable copies on both platforms;
/// * **open-with** (`app_links`), which hands over a `content://` or `file://`
///   URI — on Android a content URI is read back through the platform's
///   `ContentResolver`;
/// * the **`velorki/files` method channel**, which is how iOS reports
///   `application(_:open:options:)` for "Open in Velorki"; the share sheet
///   arrives through the Share Extension and `receive_sharing_intent`.
///
/// Whatever arrives is read into bytes, sniffed (never trusting the MIME type
/// the sender claimed) and decoded; the result appears on [imports]. Links
/// that are not files — `velorki://oauth/...`, `velorki://s/<id>` — are not
/// this feature's business and are passed through on [deepLinks] for the
/// integrations and share-link features to pick up later.
///
/// Files that cannot be read or decoded are logged and dropped rather than
/// thrown: a broken file the user did not even mean to open must not take the
/// app down at launch.
class IncomingFileService {
  /// Creates a service over [sources].
  IncomingFileService(this._sources);

  final IncomingSources _sources;
  final StreamController<ImportCandidate> _imports =
      StreamController<ImportCandidate>.broadcast();
  final StreamController<ImportException> _rejections =
      StreamController<ImportException>.broadcast();
  final StreamController<Uri> _deepLinks = StreamController<Uri>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _started = false;

  /// Every file that arrived and decoded, in arrival order.
  Stream<ImportCandidate> get imports => _imports.stream;

  /// Every file that arrived and was refused, with why: not a track, broken,
  /// empty, or unreadable. The app says so, because a rider who just tapped
  /// "Open in Velorki" and sees nothing happen is left guessing.
  Stream<ImportException> get rejections => _rejections.stream;

  /// Incoming links that are not files, for features that own them.
  Stream<Uri> get deepLinks => _deepLinks.stream;

  /// Subscribes to all three sources and drains what the app was launched
  /// with. Calling it twice does nothing.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _subscriptions.add(
      _sources.sharedMediaStream().listen(
        (files) => unawaited(_handleSharedMedia(files, 'share')),
        onError: (Object e) => _log.warning('share stream failed', e),
      ),
    );
    _subscriptions.add(
      _sources.linkStream().listen(
        (uri) => unawaited(handleUri(uri, sourceHint: 'open')),
        onError: (Object e) => _log.warning('link stream failed', e),
      ),
    );
    _subscriptions.add(
      _sources.openedFilePaths().listen(
        (path) => unawaited(handlePath(path, sourceHint: 'open')),
        onError: (Object e) => _log.warning('file channel failed', e),
      ),
    );

    // The launch intent is not replayed on the streams, so it has to be asked
    // for separately. Both calls are allowed to fail: a cold start must not
    // depend on a plugin answering.
    try {
      await _handleSharedMedia(await _sources.initialSharedMedia(), 'share');
    } on Object catch (e) {
      _log.warning('initial shared media failed', e);
    }
    try {
      final uri = await _sources.initialLink();
      if (uri != null) await handleUri(uri, sourceHint: 'open');
    } on Object catch (e) {
      _log.warning('initial link failed', e);
    }
  }

  /// Handles one incoming [uri].
  ///
  /// `file://` and `content://` are read and decoded; anything else is a deep
  /// link and goes to [deepLinks] untouched.
  Future<void> handleUri(Uri uri, {String? sourceHint}) async {
    switch (uri.scheme) {
      case 'file':
        await handlePath(uri.toFilePath(), sourceHint: sourceHint);
      case 'content':
        await _emit(
          await _sources.readContentUri(uri),
          fileName: _fileNameOf(uri),
          sourceHint: sourceHint,
        );
      default:
        _deepLinks.add(uri);
    }
  }

  /// Reads the file at [path], decodes it and emits it on [imports].
  Future<void> handlePath(String path, {String? sourceHint}) async => _emit(
    await _sources.readFile(path),
    fileName: _fileNameOfPath(path),
    sourceHint: sourceHint,
  );

  /// Reports a refusal that happened before there were bytes to decode: a
  /// link that could not be fetched, a route only its owner may open.
  void reject(ImportException rejection) {
    if (_rejections.isClosed) return;
    _log.info(
      '${rejection.fileName} was not imported: ${rejection.failure.name}',
    );
    _rejections.add(rejection);
  }

  /// Decodes [bytes] and emits the result on [imports].
  ///
  /// The file picker uses this: it already has the bytes, so it needs neither
  /// a URI nor the platform channels.
  Future<void> addBytes(
    Uint8List bytes, {
    required String fileName,
    String? sourceHint,
  }) => _emit(bytes, fileName: fileName, sourceHint: sourceHint);

  /// Stops listening and closes both streams.
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _imports.close();
    await _rejections.close();
    await _deepLinks.close();
  }

  Future<void> _handleSharedMedia(
    List<SharedMediaFile> files,
    String sourceHint,
  ) async {
    for (final file in files) {
      // The plugin also reports shared text and URLs; a URL that points at a
      // file still has to go through the URI path.
      switch (file.type) {
        case SharedMediaType.text:
          continue;
        case SharedMediaType.url:
          final uri = Uri.tryParse(file.path);
          if (uri != null) await handleUri(uri, sourceHint: sourceHint);
        case SharedMediaType.image:
        case SharedMediaType.video:
        case SharedMediaType.file:
          await handlePath(file.path, sourceHint: sourceHint);
      }
    }
  }

  Future<void> _emit(
    Uint8List? bytes, {
    required String fileName,
    String? sourceHint,
  }) async {
    if (_imports.isClosed) return;
    if (bytes == null || bytes.isEmpty) {
      _log.warning('$fileName could not be read');
      _rejections.add(
        ImportException(ImportFailure.unreadable, fileName: fileName),
      );
      return;
    }
    try {
      _imports.add(
        decodeCandidate(bytes, fileName: fileName, sourceHint: sourceHint),
      );
    } on ImportException catch (e) {
      // Not a track file, or a broken one. The user may well have shared
      // something else into the app by accident; the import screen says so.
      _log.info('$fileName was not imported: ${e.failure.name}', e.cause);
      _rejections.add(e);
    }
  }

  String _fileNameOf(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return 'import';
    return _fileNameOfPath(Uri.decodeComponent(segments.last));
  }

  String _fileNameOfPath(String path) {
    final normalised = path.replaceAll('\\', '/');
    final slash = normalised.lastIndexOf('/');
    final name = slash < 0 ? normalised : normalised.substring(slash + 1);
    return name.isEmpty ? 'import' : name;
  }
}

/// The app's incoming-file service, wired to the real platform sources.
///
/// Kept alive for the whole process: it must be listening before the first
/// frame so a cold start through "open with" is not lost.
@Riverpod(keepAlive: true)
IncomingFileService incomingFileService(Ref ref) {
  final service = IncomingFileService(PlatformIncomingSources());
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
}

/// Files that arrived and decoded, as a stream the router listens to.
@Riverpod(keepAlive: true)
Stream<ImportCandidate> incomingImports(Ref ref) =>
    ref.watch(incomingFileServiceProvider).imports;

/// Files that arrived and were refused, for the screen that says so.
@Riverpod(keepAlive: true)
Stream<ImportException> incomingImportRejections(Ref ref) =>
    ref.watch(incomingFileServiceProvider).rejections;

/// Incoming links that are not files; OAuth callbacks and share links will be
/// read off this in later milestones.
@Riverpod(keepAlive: true)
Stream<Uri> incomingDeepLinks(Ref ref) =>
    ref.watch(incomingFileServiceProvider).deepLinks;
