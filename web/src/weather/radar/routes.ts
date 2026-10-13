// SPDX-License-Identifier: AGPL-3.0-only
import { LIMITS } from '@/server/ratelimit';
import { getDpc, getOpera } from '@/server/singletons';
import type { RadarRoutes } from './http';

/** EUMETNET OPERA's composite over Europe: `/weather/radar/opera/*`. */
export const OPERA_ROUTES: RadarRoutes = {
  store: getOpera,
  limits: {
    perIpHour: LIMITS.radarPerIpHour,
    perMin: LIMITS.radarPerMin,
    perDay: LIMITS.radarPerDay,
  },
};

/** The DPC's rainfall over Italy: `/weather/radar/dpc/*`. */
export const DPC_ROUTES: RadarRoutes = {
  store: getDpc,
  limits: {
    perIpHour: LIMITS.dpcRadarPerIpHour,
    perMin: LIMITS.dpcRadarPerMin,
    perDay: LIMITS.dpcRadarPerDay,
  },
};
