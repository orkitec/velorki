// SPDX-License-Identifier: AGPL-3.0-only
import { radarFramesRoute } from '@/weather/radar/http';
import { OPERA_ROUTES } from '@/weather/radar/routes';

/**
 * The OPERA radar composite's frames of the last two hours, oldest first, and
 * the newest of them: the app asks no image past it.
 */
export const GET = radarFramesRoute(OPERA_ROUTES);
