// SPDX-License-Identifier: AGPL-3.0-only

/**
 * Process boot.
 *
 * Next calls `register()` once per runtime per process. Everything here is
 * node-only: the edge copy of the app has no SQLite, no pino and no cache.
 */
export async function register(): Promise<void> {
  if (process.env.NEXT_RUNTIME !== 'nodejs') return;

  const { llmConfigured, rwgpsConfigured, stravaConfigured, workerId } = await import('@/config');
  const { getConfig, getCounters, getLogger, getStore } = await import('@/server/singletons');
  const { startSweep } = await import('@/share/store');

  const config = getConfig();
  const log = getLogger();

  if (config.COUNTERS === 'orkify') {
    try {
      const { cache } = await import('@orkify/cache');
      cache.configure({ fileBacked: false });
    } catch {
      // Already configured (the ISR cache handler got there first) - fine.
    }
  }

  // One line at boot that makes a misconfigured deploy obvious, without
  // printing any of the values themselves.
  log.info(
    {
      version: config.APP_VERSION,
      strava: stravaConfigured(config),
      rwgps: rwgpsConfigured(config),
      llm: llmConfigured(config),
      brouter: config.BROUTER_URL !== undefined,
      revenuecatStub: config.REVENUECAT_MODE === 'stub',
      trustProxy: config.TRUST_PROXY,
      devHosts: config.DEV_HOSTS,
      counters: config.COUNTERS,
      // No `worker` here: the logger's `base` already carries it, and a second
      // one would be emitted as a duplicate JSON key.
    },
    'velorki web starting',
  );

  // Expired shares disappear from reads immediately; this reclaims the space.
  // One worker owns the chore (worker 0), and a counter makes sure a restart
  // loop cannot run it again and again: the first caller of the day wins.
  if (workerId(config) !== '0') return;
  const day = new Date().toISOString().slice(0, 10);
  const claim = await getCounters().incr(`share:sweep:${day}`, 1, { ttlIfNew: 2 * 24 * 60 * 60 });
  if (claim !== 1) return;

  startSweep(getStore(), (deleted) => {
    log.info({ deleted }, 'swept expired shares');
  });
}
