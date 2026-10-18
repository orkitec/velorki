import 'dart:js_interop';
import 'dart:typed_data';

import 'package:velorki_io/io.dart';
import 'package:web/web.dart' as web;

/// The URL the map loads the file at [path] from: a blob: URL holding a
/// copy of its bytes, which the page keeps until [releaseLocalFileUrl].
String localFileUrl(String path) =>
    _blobUrl(File(path).readAsBytesSync(), 'application/geo+json');

/// The URL the map loads the PNG [bytes] from, kept as [localFileUrl]'s.
String pngBytesUrl(Uint8List bytes) => _blobUrl(bytes, 'image/png');

String _blobUrl(Uint8List bytes, String type) => web.URL.createObjectURL(
  web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: type)),
);

/// Lets go of a URL [localFileUrl] or [pngBytesUrl] gave, once no source
/// uses it.
void releaseLocalFileUrl(String url) => web.URL.revokeObjectURL(url);
