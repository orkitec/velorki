// SPDX-License-Identifier: AGPL-3.0-only
import Fastify, { type FastifyInstance } from 'fastify';
import { loadConfig, type Config } from './config.js';
import { DailyBudget, createModelFactory, loadPrompts, type ModelFactory, type Prompts } from './ai/provider.js';
import { EntitlementService } from './plugins/entitlement.js';
import { registerErrorHandler } from './plugins/errors.js';
import { registerRequestId, requestIdFrom } from './plugins/requestid.js';
import { registerAiRoutes } from './routes/ai.js';
import { registerHealthRoutes } from './routes/health.js';
import { registerOAuthRoutes } from './routes/oauth.js';
import { registerShareRoutes } from './routes/share.js';
import { ShareStore, startSweep } from './share/store.js';
import { RateLimiter } from './util/tokenbucket.js';

/** Everything the route modules need, assembled once per app instance. */
export interface AppContext {
  config: Config;
  limiter: RateLimiter;
  entitlement: EntitlementService;
  shares: ShareStore;
  getModel: ModelFactory;
  prompts: Prompts;
  budget: DailyBudget;
}

declare module 'fastify' {
  interface FastifyInstance {
    velorki: AppContext;
  }
}

export interface BuildAppOptions {
  config?: Config;
  /** Injected by tests to run against a mock language model. */
  getModel?: ModelFactory;
  prompts?: Prompts;
  shares?: ShareStore;
  limiter?: RateLimiter;
  entitlement?: EntitlementService;
  budget?: DailyBudget;
  /** `false` silences logging in tests. */
  logger?: boolean;
}

/**
 * Build the Fastify instance. Kept separate from server.ts so tests can use
 * `app.inject()` without binding a port.
 */
export function buildApp(opts: BuildAppOptions = {}): FastifyInstance {
  const config = opts.config ?? loadConfig();

  const app = Fastify({
    // X-Forwarded-For is only believed behind a trusted proxy.
    trustProxy: config.TRUST_PROXY,
    // Reuse the caller's X-Request-Id so a trace spans app and server.
    genReqId: (req) => requestIdFrom(req as unknown as { headers: Record<string, unknown> }),
    logger:
      opts.logger === false
        ? false
        : {
            level: config.LOG_LEVEL,
            // Credentials must never reach the log, not even at trace level.
            redact: {
              paths: [
                'req.headers.authorization',
                'req.headers.cookie',
                'res.headers["set-cookie"]',
              ],
              censor: '[redacted]',
            },
          },
  });

  const ctx: AppContext = {
    config,
    limiter: opts.limiter ?? new RateLimiter(),
    entitlement: opts.entitlement ?? new EntitlementService(config),
    shares: opts.shares ?? new ShareStore(config.SHARE_DB_PATH),
    getModel: opts.getModel ?? createModelFactory(config),
    prompts: opts.prompts ?? loadPrompts(),
    budget: opts.budget ?? new DailyBudget(config),
  };

  app.decorate('velorki', ctx);
  // Declared up front so every request object has the same shape.
  app.decorateRequest('appUserId', null);

  // Registered directly on the root instance rather than via `register()`:
  // these hooks must apply to every route, not to an encapsulated child scope.
  registerRequestId(app);
  registerErrorHandler(app);

  registerHealthRoutes(app, ctx);
  registerOAuthRoutes(app, ctx);
  registerAiRoutes(app, ctx);
  registerShareRoutes(app, ctx);

  // Expired shares disappear from reads immediately; this reclaims the space.
  const stopSweep = startSweep(ctx.shares, (deleted) => {
    app.log.info({ deleted }, 'swept expired shares');
  });

  app.addHook('onClose', async () => {
    stopSweep();
    // Only close a store this app created; an injected one belongs to the test.
    if (opts.shares === undefined) ctx.shares.close();
  });

  return app;
}
