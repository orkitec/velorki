'use client';
// SPDX-License-Identifier: AGPL-3.0-only
import dynamic from 'next/dynamic';
import styles from './share.module.css';

/**
 * MapLibre is ~200 kB of browser-only code that touches `window` on import, so
 * the canvas is pulled in lazily and never rendered on the server.
 */
const MapCanvas = dynamic(() => import('./MapCanvas'), {
  ssr: false,
  loading: () => <div className={styles.map} />,
});

export default function ShareMap({ id }: { id: string }) {
  return <MapCanvas id={id} />;
}
