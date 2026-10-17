import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:velorki_io/memory_fs.dart';
import 'package:web/web.dart' as web;

/// Keeps the downloaded routing tiles and gazetteers across visits, in the
/// browser's Cache Storage, so a second visit routes without downloading
/// Madeira again.
///
/// The app reads and writes files through `package:velorki_io`, which in a
/// browser is [MemoryFileSystem]. This store copies every finished `.rd5`
/// and `.gaz` it is told about into the cache, and puts them back into the
/// memory before the app starts. A partial download (`.part`) is not kept:
/// a page closed mid-download starts that tile again.
abstract final class WebFileStore {
  static const String _cacheName = 'velorki-files-v1';

  /// The cache keys are URLs; this prefix under the page's origin is never
  /// fetched, it only names the entries.
  static String get _prefix => '${web.window.location.origin}/.velorki-files';

  static bool _keeps(String path) =>
      (path.startsWith('/support/brouter/segments/') &&
          path.endsWith('.rd5')) ||
      (path.startsWith('/support/brouter/gazetteer/') && path.endsWith('.gaz'));

  /// Loads what was kept, then keeps what changes. A browser without Cache
  /// Storage (a page not served over https or from localhost) keeps nothing
  /// and the app downloads again on the next visit.
  static Future<void> open() async {
    // Files in bytes JavaScript holds, as the kept ones come back: sqlite
    // reads a gazetteer page by page into its own memory, which from Dart's
    // bytes went element by element and froze the page for a minute.
    MemoryFileSystem.newBytes = (length) =>
        JSUint8Array.withLength(length).toDart;
    final web.Cache cache;
    try {
      cache = await web.window.caches.open(_cacheName).toDart;
    } on Object catch (e) {
      debugPrint('velorki: no Cache Storage, files last one visit: $e');
      return;
    }
    var restored = 0;
    for (final request in (await cache.keys().toDart).toDart) {
      final url = request.url;
      if (!url.startsWith(_prefix)) continue;
      final response = await cache.match(request).toDart;
      if (response == null) continue;
      final buffer = (await response.arrayBuffer().toDart).toDart;
      MemoryFileSystem.seed(
        url.substring(_prefix.length),
        buffer.asUint8List(),
      );
      restored++;
    }
    debugPrint('velorki: $restored kept files restored');
    MemoryFileSystem.onChange = (path, bytes) {
      if (_keeps(path)) unawaited(_store(cache, path, bytes));
    };
  }

  static Future<void> _store(web.Cache cache, String path, Uint8List? bytes) {
    final key = '$_prefix$path'.toJS;
    return Future(() async {
      if (bytes == null) {
        await cache.delete(key).toDart;
      } else {
        await cache.put(key, web.Response(bytes.toJS)).toDart;
      }
    }).catchError((Object e) {
      debugPrint('velorki: $path not kept: $e');
    });
  }
}
