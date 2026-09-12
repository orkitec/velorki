import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link in the browser; `false` when nothing could handle it.
typedef LinkOpener = Future<bool> Function(Uri url);

/// Opens [url] in whatever the platform uses for web pages.
Future<bool> openExternalLink(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// The link opener. Overridden in widget tests so no browser is launched.
final linkOpenerProvider = Provider<LinkOpener>((ref) => openExternalLink);
