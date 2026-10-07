import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link in the browser; `false` when nothing could handle it.
typedef LinkOpener = Future<bool> Function(Uri url);

/// Opens [url] in whatever the platform uses for web pages.
Future<bool> openExternalLink(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// The link opener. Overridden in widget tests so no browser is launched.
final linkOpenerProvider = Provider<LinkOpener>((ref) => openExternalLink);

/// Says whether an app can handle a link; `false` when that cannot be
/// told.
typedef LinkProbe = Future<bool> Function(Uri url);

/// Asks the platform whether anything handles [url].
Future<bool> canOpenLink(Uri url) async {
  try {
    return await canLaunchUrl(url);
  } on Object {
    return false;
  }
}

/// The link probe. Overridden in widget tests, where no plugin answers.
final linkProbeProvider = Provider<LinkProbe>((ref) => canOpenLink);
