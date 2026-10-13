// SPDX-License-Identifier: AGPL-3.0-only
import { radarFramesRoute } from '@/weather/radar/http';
import { DPC_ROUTES } from '@/weather/radar/routes';

/**
 * The DPC's rainfall over Italy, its frames of the last two hours, oldest
 * first, and the newest of them: the app asks no image past it.
 */
export const GET = radarFramesRoute(DPC_ROUTES);
