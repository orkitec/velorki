import 'dart:convert';
import 'dart:typed_data';

/// The URL the map loads the file at [path] from.
String localFileUrl(String path) => Uri.file(path).toString();

/// The URL the map loads the PNG [bytes] from.
String pngBytesUrl(Uint8List bytes) =>
    'data:image/png;base64,${base64Encode(bytes)}';

/// Lets go of a URL [localFileUrl] or [pngBytesUrl] gave, once no source
/// uses it.
void releaseLocalFileUrl(String url) {}
