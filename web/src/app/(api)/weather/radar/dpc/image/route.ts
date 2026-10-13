// SPDX-License-Identifier: AGPL-3.0-only
import { radarImageRoute } from '@/weather/radar/http';
import { DPC_ROUTES } from '@/weather/radar/routes';

/**
 * One image of a Web Mercator box at one frame of the DPC's rainfall over
 * Italy, drawn from it alone (CC BY-SA 4.0: never composited with another
 * source), in the DWD radar's classes and colours, no data grey, dry and
 * beyond its grid transparent (see `src/weather/radar/render.ts`).
 */
export const GET = radarImageRoute(DPC_ROUTES);
