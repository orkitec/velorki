/// The project's own web pages.
///
/// They are referenced from the paywall, from Settings → About and from both
/// store listings, and the store review checks that they are reachable, so
/// they live in one place rather than in each feature.
library;

/// The terms of use. Linked from the paywall and from Settings → About.
const String velorkiTermsUrl = 'https://velorki.com/terms';

/// The privacy policy. Linked from the paywall, from Settings → About and
/// from both store listings; `docs/PRIVACY.md` is its source.
const String velorkiPrivacyUrl = 'https://velorki.com/privacy';

/// The issue tracker, where "Report a problem" in Settings → About leads.
const String velorkiIssuesUrl = 'https://github.com/orkitec/velorki/issues';

/// OpenStreetMap's copyright and licence page, where the OSM credit in
/// Settings → About leads.
const String osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// Where riders write to: support, questions, deletion requests.
const String velorkiSupportEmail = 'ride@velorki.com';

/// The site's download page in [languageCode], as the site's own paths are:
/// English unprefixed, every other language under its code. Where the web
/// planner sends a rider for what only the phone apps have.
String velorkiDownloadUrl(String languageCode) =>
    _sitePage(languageCode, 'download');

/// The imprint (§ 5 DDG) in [languageCode]. Linked from Settings → About and,
/// on the web, from the map's attribution, so it is two taps from anywhere.
String velorkiImprintUrl(String languageCode) =>
    _sitePage(languageCode, 'imprint');

String _sitePage(String languageCode, String page) => languageCode == 'en'
    ? 'https://velorki.com/$page'
    : 'https://velorki.com/$languageCode/$page';
