// SPDX-License-Identifier: AGPL-3.0-only
import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { llmConfigured, rwgpsConfigured, stravaConfigured } from './config.js';

/**
 * Process entry point. Orkify runs `npm run build` and then
 * `node dist/server.js`; configuration arrives through process.env and the
 * container is stopped with SIGTERM.
 */

const SHUTDOWN_GRACE_MS = 10_000;

async function main(): Promise<void> {
  const config = loadConfig();
  const app = buildApp({ config });

  // One line at boot that makes a misconfigured deploy obvious, without
  // printing any of the values themselves.
  app.log.info(
    {
      version: config.APP_VERSION,
      strava: stravaConfigured(config),
      rwgps: rwgpsConfigured(config),
      llm: llmConfigured(config),
      brouter: config.BROUTER_URL !== undefined,
      revenuecat: config.REVENUECAT_MODE,
      trustProxy: config.TRUST_PROXY,
    },
    'velorki api starting',
  );

  let shuttingDown = false;
  const shutdown = (signal: string): void => {
    if (shuttingDown) return;
    shuttingDown = true;
    app.log.info({ signal }, 'shutting down');

    // Hard deadline: if in-flight SSE streams refuse to finish, exit anyway so
    // the orchestrator does not have to SIGKILL us.
    const deadline = setTimeout(() => {
      app.log.error('graceful shutdown timed out, exiting');
      process.exit(1);
    }, SHUTDOWN_GRACE_MS);
    deadline.unref();

    app
      .close()
      .then(() => {
        clearTimeout(deadline);
        process.exit(0);
      })
      .catch((err: unknown) => {
        app.log.error({ err }, 'error during shutdown');
        process.exit(1);
      });
  };

  process.on('SIGTERM', () => {
    shutdown('SIGTERM');
  });
  process.on('SIGINT', () => {
    shutdown('SIGINT');
  });

  await app.listen({ port: config.PORT, host: config.HOST });
}

main().catch((err: unknown) => {
  // The logger may not exist yet (bad config), so this one goes to stderr.
  console.error('velorki api failed to start:', err);
  process.exit(1);
});
