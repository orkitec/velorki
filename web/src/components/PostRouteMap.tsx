'use client';
// SPDX-License-Identifier: AGPL-3.0-only
import dynamic from 'next/dynamic';

/** The map's box: the docs' panel, a fixed height so the page does not jump. */
const BOX = 'panel h-80 overflow-hidden sm:h-96';

/**
 * The route of a ride post, drawn by the share page's map
 * (RouteMapCanvas.tsx), and loaded the same way: in the browser only, with an
 * empty box of the same size holding the space until MapLibre arrives.
 */
const RouteMapCanvas = dynamic(() => import('./RouteMapCanvas'), {
  ssr: false,
  loading: () => <div className={BOX} />,
});

export function PostRouteMap({ gpxUrl, label, errorMessage }: { gpxUrl: string; label: string; errorMessage: string }) {
  return (
    <RouteMapCanvas
      gpxUrl={gpxUrl}
      className={BOX}
      errorClassName="panel p-5 text-sm text-muted"
      errorMessage={errorMessage}
      label={label}
    />
  );
}
