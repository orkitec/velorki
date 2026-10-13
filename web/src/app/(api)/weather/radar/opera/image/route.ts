// SPDX-License-Identifier: AGPL-3.0-only
import { radarImageRoute } from '@/weather/radar/http';
import { OPERA_ROUTES } from '@/weather/radar/routes';

/**
 * One image of a Web Mercator box at one OPERA frame, the rain in the DWD
 * radar's classes and colours, no data grey, dry and beyond the composite
 * transparent (see `src/weather/radar/render.ts`).
 */
export const GET = radarImageRoute(OPERA_ROUTES);
