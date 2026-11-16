'use client';
// SPDX-License-Identifier: AGPL-3.0-only
import dynamic from 'next/dynamic';
import styles from './share.module.css';

/**
 * MapLibre is ~200 kB of browser-only code that touches `window` on import, so
 * the canvas is pulled in lazily and never rendered on the server. The canvas
 * is shared with the blog's ride posts (src/components/RouteMapCanvas.tsx).
 */
const MapCanvas = dynamic(() => import('@/components/RouteMapCanvas'), {
  ssr: false,
  loading: () => <div className={styles.map} />,
});

export default function ShareMap({ id }: { id: string }) {
  return (
    <MapCanvas
      gpxUrl={`/s/${id}.gpx`}
      className={styles.map}
      errorClassName={styles.mapError}
      errorMessage="The map could not be loaded. You can still download the GPX file below."
    />
  );
}
