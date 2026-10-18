import 'dart:js_interop';

import 'package:velorki_io/io.dart';
import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

/// Hands [file] to the browser as a download: the web's share sheet.
Future<void> downloadFile(File file, {required String mimeType}) async {
  final bytes = await file.readAsBytes();
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = p.basename(file.path)
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Revoked on the next turn, once the browser has taken the download.
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
}
