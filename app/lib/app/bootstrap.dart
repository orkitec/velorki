import 'proprietary_services.dart';
import 'startup.dart';

/// The app's start as the App Store and Google Play builds have it: every
/// service, the six closed-source plugins included.
///
/// `main.dart` calls this on a phone or a tablet and `bootstrap_web.dart` in a
/// browser; `main_fdroid.dart` calls [startVelorki] on its own instead, which
/// is what keeps those plugins out of that build.
Future<void> bootstrap() =>
    startVelorki(overrides: proprietaryServiceOverrides());
