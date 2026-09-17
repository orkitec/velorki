'use client';
// SPDX-License-Identifier: AGPL-3.0-only
import { useEffect, useRef, useState } from 'react';
import { LngLatBounds, Map as MapLibreMap, Marker, NavigationControl } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import styles from './share.module.css';

/**
 * The map on the share page.
 *
 * Loaded only in the browser (`next/dynamic` with `ssr: false` in ShareMap), so
 * MapLibre is never part of the server bundle and never blocks the static
 * shell. The GPX is parsed here, exactly as the Fastify page's inline script
 * did: the server only ever stores and serves the original file.
 */

const MAP_STYLE = 'https://tiles.openfreemap.org/styles/liberty';
const ROUTE_COLOR = '#d1481f';
const START_COLOR = '#2e7d32';

type Coord = [number, number];

export function coordsFromGpx(text: string): Coord[] {
  const doc = new DOMParser().parseFromString(text, 'application/xml');
  if (doc.getElementsByTagName('parsererror').length > 0) return [];
  const out: Coord[] = [];
  // Prefer track points; only fall back to routes, then waypoints.
  for (const tag of ['trkpt', 'rtept', 'wpt']) {
    const pts = doc.getElementsByTagName(tag);
    if (pts.length === 0) continue;
    for (let i = 0; i < pts.length; i += 1) {
      const el = pts[i];
      if (el === undefined) continue;
      const lat = Number.parseFloat(el.getAttribute('lat') ?? '');
      const lon = Number.parseFloat(el.getAttribute('lon') ?? '');
      if (Number.isFinite(lat) && Number.isFinite(lon)) out.push([lon, lat]);
    }
    if (out.length > 1) break;
  }
  return out;
}

export default function MapCanvas({ id }: { id: string }) {
  const container = useRef<HTMLDivElement | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let map: MapLibreMap | undefined;
    let cancelled = false;

    async function draw(): Promise<void> {
      const res = await fetch(`/s/${id}.gpx`);
      if (!res.ok) throw new Error(`gpx ${String(res.status)}`);
      const coords = coordsFromGpx(await res.text());
      const first = coords[0];
      const last = coords[coords.length - 1];
      if (coords.length < 2 || first === undefined || last === undefined) {
        throw new Error('no usable points');
      }
      if (cancelled || container.current === null) return;

      const bounds = coords.reduce(
        (b, c) => b.extend(c),
        new LngLatBounds(first, first),
      );

      map = new MapLibreMap({
        container: container.current,
        style: MAP_STYLE,
        bounds,
        fitBoundsOptions: { padding: 40, maxZoom: 15 },
        attributionControl: { compact: true },
      });
      map.addControl(new NavigationControl({ showCompass: false }), 'top-right');
      // Tile hiccups must not blank the page.
      map.on('error', () => undefined);

      map.on('load', () => {
        if (map === undefined) return;
        map.addSource('route', {
          type: 'geojson',
          data: {
            type: 'Feature',
            properties: {},
            geometry: { type: 'LineString', coordinates: coords },
          },
        });
        // A wide casing under a narrower line keeps the track readable on any basemap.
        map.addLayer({
          id: 'route-casing',
          type: 'line',
          source: 'route',
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': '#ffffff', 'line-width': 7, 'line-opacity': 0.9 },
        });
        map.addLayer({
          id: 'route-line',
          type: 'line',
          source: 'route',
          layout: { 'line-cap': 'round', 'line-join': 'round' },
          paint: { 'line-color': ROUTE_COLOR, 'line-width': 4 },
        });
        new Marker({ color: START_COLOR }).setLngLat(first).addTo(map);
        new Marker({ color: ROUTE_COLOR }).setLngLat(last).addTo(map);
      });
    }

    void draw().catch(() => {
      if (!cancelled) setFailed(true);
    });

    return () => {
      cancelled = true;
      map?.remove();
    };
  }, [id]);

  if (failed) {
    return (
      <div className={styles.mapError}>
        The map could not be loaded. You can still download the GPX file below.
      </div>
    );
  }
  return <div className={styles.map} ref={container} />;
}
