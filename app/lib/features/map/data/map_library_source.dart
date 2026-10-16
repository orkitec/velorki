import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// The site's own copy of maplibre-gl-js and its licence, under the web
/// build's root (`web/maplibre-gl/`, put there by `tool/web_assets.sh`).
/// The licence page has it from maplibre_gl's own licence.
const String _mapLibraryDirectory = 'maplibre-gl';

/// Has the map load maplibre-gl-js from the site itself rather than from
/// the plugin's CDN, so the page needs no third party to draw a map and its
/// Content-Security-Policy can name only what the app loads. [siteRoot] is
/// the page's base URL. Called once, before the first map, by the browser's
/// bootstrap.
void loadMapLibraryFromSite(Uri siteRoot) {
  final dir = siteRoot.resolve('$_mapLibraryDirectory/');
  ml.MapLibreMap.webLibrarySource = ml.MapLibreJsSource.urls(
    scriptUrl: dir.resolve('maplibre-gl.mjs').toString(),
    styleUrl: dir.resolve('maplibre-gl.css').toString(),
  );
}
