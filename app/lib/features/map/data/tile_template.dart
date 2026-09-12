/// Helpers for XYZ raster tile URL templates.
library;

/// The subdomains CyclOSM (and most OSM raster services) round-robin over.
const List<String> defaultTileSubdomains = <String>['a', 'b', 'c'];

/// Expands the `{s}` subdomain placeholder into one URL per subdomain.
///
/// MapLibre's raster source takes a list of templates and picks between them
/// itself; it does not understand `{s}`. A template without `{s}` yields a
/// single URL.
List<String> expandTileTemplate(
  String template, {
  List<String> subdomains = defaultTileSubdomains,
}) {
  if (template.isEmpty) return const <String>[];
  if (!template.contains('{s}')) return <String>[template];
  if (subdomains.isEmpty) return const <String>[];
  return subdomains.map((s) => template.replaceAll('{s}', s)).toList();
}
