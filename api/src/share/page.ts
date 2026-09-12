// SPDX-License-Identifier: AGPL-3.0-only
import type { ShareRecord } from './store.js';

/**
 * The public share page.
 *
 * Self-contained by design: all CSS and JS is inline, and the only external
 * resources are the pinned MapLibre GL bundle and the OpenFreeMap style. No
 * analytics, no fonts, no trackers — the page is handed to people who never
 * agreed to anything.
 */

const MAPLIBRE_VERSION = '6.9.0';
const MAPLIBRE_JS = `https://unpkg.com/maplibre-gl@${MAPLIBRE_VERSION}/dist/maplibre-gl.js`;
const MAPLIBRE_CSS = `https://unpkg.com/maplibre-gl@${MAPLIBRE_VERSION}/dist/maplibre-gl.css`;
const MAP_STYLE = 'https://tiles.openfreemap.org/styles/liberty';

export function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatDistance(km: number): string {
  return `${km.toFixed(1)} km`;
}

function formatAscent(m: number): string {
  return `${Math.round(m)} m`;
}

function formatDuration(seconds: number): string {
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const min = Math.floor((total % 3600) / 60);
  return h > 0 ? `${h} h ${String(min).padStart(2, '0')} min` : `${min} min`;
}

export function renderSharePage(record: ShareRecord): string {
  const title = escapeHtml(record.name || 'Velorki route');
  const kind = record.kind === 'ride' ? 'Ride' : 'Route';

  const stats: { label: string; value: string }[] = [
    { label: 'Distance', value: formatDistance(record.summary.distance_km) },
  ];
  if (record.summary.ascent_m !== undefined) {
    stats.push({ label: 'Ascent', value: formatAscent(record.summary.ascent_m) });
  }
  if (record.summary.duration_s !== undefined) {
    stats.push({ label: 'Duration', value: formatDuration(record.summary.duration_s) });
  }

  const statsHtml = stats
    .map(
      (s) =>
        `<div class="stat"><span class="stat-label">${escapeHtml(s.label)}</span><span class="stat-value">${escapeHtml(s.value)}</span></div>`,
    )
    .join('');

  // record.id is validated base62, so it is safe in both the URL and the script.
  const id = record.id;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} - Velorki</title>
<meta name="robots" content="noindex">
<link rel="stylesheet" href="${MAPLIBRE_CSS}">
<style>
  :root {
    color-scheme: light dark;
    --bg: #ffffff;
    --fg: #16181d;
    --muted: #5d6470;
    --line: #e3e6ea;
    --accent: #d1481f;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #14161a; --fg: #eceef1; --muted: #9aa2ae; --line: #2a2e35; --accent: #ff7a4d; }
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font: 15px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    display: flex;
    flex-direction: column;
  }
  header { padding: 16px 20px 12px; border-bottom: 1px solid var(--line); }
  .kind { font-size: 12px; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }
  h1 { margin: 2px 0 10px; font-size: 21px; line-height: 1.25; font-weight: 600; overflow-wrap: anywhere; }
  .stats { display: flex; flex-wrap: wrap; gap: 20px; }
  .stat { display: flex; flex-direction: column; }
  .stat-label { font-size: 11px; letter-spacing: .06em; text-transform: uppercase; color: var(--muted); }
  .stat-value { font-size: 17px; font-weight: 600; font-variant-numeric: tabular-nums; }
  #map { flex: 1 1 auto; min-height: 280px; background: var(--line); }
  #map-error { display: none; padding: 20px; color: var(--muted); }
  footer { display: flex; flex-wrap: wrap; gap: 10px; padding: 14px 20px; border-top: 1px solid var(--line); }
  a.btn {
    display: inline-block; padding: 10px 16px; border-radius: 10px;
    text-decoration: none; font-weight: 600; font-size: 14px;
    border: 1px solid var(--line); color: var(--fg);
  }
  a.btn.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  .credit { margin-left: auto; align-self: center; font-size: 12px; color: var(--muted); }
  .credit a { color: inherit; }
</style>
</head>
<body>
<header>
  <div class="kind">${kind} shared from Velorki</div>
  <h1>${title}</h1>
  <div class="stats">${statsHtml}</div>
</header>

<div id="map"></div>
<div id="map-error">The map could not be loaded. You can still download the GPX file below.</div>

<footer>
  <a class="btn primary" href="velorki://share/${id}">Open in Velorki</a>
  <a class="btn" href="/s/${id}.gpx" download>Download GPX</a>
  <span class="credit">Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors</span>
</footer>

<script src="${MAPLIBRE_JS}"></script>
<script>
(function () {
  var shareId = ${JSON.stringify(id)};
  var mapEl = document.getElementById('map');
  var errEl = document.getElementById('map-error');

  function fail() {
    mapEl.style.display = 'none';
    errEl.style.display = 'block';
  }

  if (typeof maplibregl === 'undefined') { fail(); return; }

  // Parse the GPX in the browser: the server only ever stores and serves the
  // original file, it never rewrites it.
  function coordsFromGpx(text) {
    var doc = new DOMParser().parseFromString(text, 'application/xml');
    if (doc.getElementsByTagName('parsererror').length > 0) return [];
    var out = [];
    var tags = ['trkpt', 'rtept', 'wpt'];
    for (var t = 0; t < tags.length; t++) {
      var pts = doc.getElementsByTagName(tags[t]);
      if (pts.length === 0) continue;
      for (var i = 0; i < pts.length; i++) {
        var lat = parseFloat(pts[i].getAttribute('lat'));
        var lon = parseFloat(pts[i].getAttribute('lon'));
        if (isFinite(lat) && isFinite(lon)) out.push([lon, lat]);
      }
      // Prefer track points; only fall back to routes, then waypoints.
      if (out.length > 1) break;
    }
    return out;
  }

  fetch('/s/' + shareId + '.gpx')
    .then(function (r) { if (!r.ok) throw new Error('gpx ' + r.status); return r.text(); })
    .then(function (text) {
      var coords = coordsFromGpx(text);
      if (coords.length < 2) { fail(); return; }

      var bounds = coords.reduce(function (b, c) { return b.extend(c); },
        new maplibregl.LngLatBounds(coords[0], coords[0]));

      var map = new maplibregl.Map({
        container: 'map',
        style: ${JSON.stringify(MAP_STYLE)},
        bounds: bounds,
        fitBoundsOptions: { padding: 40, maxZoom: 15 },
        attributionControl: { compact: true }
      });
      map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
      map.on('error', function () { /* tile hiccups must not blank the page */ });

      map.on('load', function () {
        map.addSource('route', {
          type: 'geojson',
          data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: coords } }
        });
        // A wide casing under a narrower line keeps the track readable on any basemap.
        map.addLayer({
          id: 'route-casing', type: 'line', source: 'route',
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': '#ffffff', 'line-width': 7, 'line-opacity': 0.9 }
        });
        map.addLayer({
          id: 'route-line', type: 'line', source: 'route',
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': '#d1481f', 'line-width': 4 }
        });
        new maplibregl.Marker({ color: '#2e7d32' }).setLngLat(coords[0]).addTo(map);
        new maplibregl.Marker({ color: '#d1481f' }).setLngLat(coords[coords.length - 1]).addTo(map);
      });
    })
    .catch(fail);
})();
</script>
</body>
</html>
`;
}
