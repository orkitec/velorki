// SPDX-License-Identifier: AGPL-3.0-only
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AppContext } from '../app.js';
import { ApiError } from '../plugins/errors.js';
import { appUserId, requireEntitlement } from '../plugins/entitlement.js';
import { rateLimit } from '../plugins/ratelimit.js';
import { LIMITS } from '../util/tokenbucket.js';
import { isValidShareId } from '../share/store.js';
import { renderSharePage } from '../share/page.js';

/** 2 MB of GPX is roughly a 100 000-point track; well past any real ride. */
export const MAX_GPX_BYTES = 2 * 1024 * 1024;

const shareBodySchema = z.object({
  kind: z.enum(['route', 'ride']),
  name: z.string().trim().min(1).max(200),
  gpx: z
    .string()
    .min(1)
    .refine((v) => Buffer.byteLength(v, 'utf8') <= MAX_GPX_BYTES, {
      message: `gpx must be at most ${String(MAX_GPX_BYTES)} bytes`,
    })
    .refine((v) => v.includes('<gpx'), { message: 'gpx must be a GPX document' }),
  summary: z.object({
    distance_km: z.number().min(0).max(100_000),
    ascent_m: z.number().min(0).max(100_000).optional(),
    duration_s: z.number().min(0).max(30 * 24 * 3600).optional(),
  }),
});

export function registerShareRoutes(app: FastifyInstance, ctx: AppContext): void {
  const entitled = requireEntitlement(ctx.entitlement);

  app.post(
    '/share',
    {
      // Fastify's default body limit is 1 MB; allow the 2 MB GPX plus JSON
      // escaping overhead. The exact limit is enforced by the schema above.
      bodyLimit: 3 * 1024 * 1024,
      preHandler: [entitled, rateLimit(ctx.limiter, [LIMITS.sharePerDay], (req) => appUserId(req))],
    },
    async (req, reply) => {
      const parsed = shareBodySchema.safeParse(req.body);
      if (!parsed.success) {
        throw new ApiError(
          'invalid_request',
          parsed.error.issues
            .map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`)
            .join('; '),
        );
      }

      // Nothing links a share row to the rider who created it: the share id is
      // the only capability, and the store holds no account identifier.
      const record = ctx.shares.create(parsed.data);
      req.log.info({ shareId: record.id, kind: record.kind }, 'share created');

      return reply.code(201).send({
        id: record.id,
        url: `${ctx.config.PUBLIC_BASE_URL}/s/${record.id}`,
      });
    },
  );

  /* ---------------------------------------------------------------- public */
  // No auth: these URLs are handed to people who do not have the app.

  app.get<{ Params: { id: string } }>('/s/:id.gpx', async (req, reply) => {
    const record = lookup(ctx, req.params.id);
    return reply
      .type('application/gpx+xml; charset=utf-8')
      .header('content-disposition', `attachment; filename="${gpxFilename(record.name, record.id)}"`)
      .header('cache-control', 'public, max-age=3600')
      .send(record.gpx);
  });

  app.get<{ Params: { id: string } }>('/s/:id', async (req, reply) => {
    const record = lookup(ctx, req.params.id);
    return reply
      .type('text/html; charset=utf-8')
      .header('cache-control', 'public, max-age=300')
      // The page inlines its own CSS/JS and loads MapLibre from unpkg.
      .header(
        'content-security-policy',
        [
          "default-src 'none'",
          "script-src 'self' 'unsafe-inline' https://unpkg.com",
          "style-src 'self' 'unsafe-inline' https://unpkg.com",
          "img-src 'self' data: blob: https://tiles.openfreemap.org",
          "connect-src 'self' https://tiles.openfreemap.org",
          "worker-src blob:",
          "base-uri 'none'",
          "form-action 'none'",
        ].join('; '),
      )
      .send(renderSharePage(record));
  });
}

/** Unknown, malformed and expired ids are all a plain 404. */
function lookup(ctx: AppContext, rawId: string) {
  const id = rawId;
  if (!isValidShareId(id)) throw new ApiError('not_found', 'No such share.');
  const record = ctx.shares.get(id);
  if (record === null) throw new ApiError('not_found', 'No such share.');
  return record;
}

/** ASCII-safe filename derived from the share name, with the id as a fallback. */
function gpxFilename(name: string, id: string): string {
  const slug = name
    .normalize('NFKD')
    .replace(/[^\w -]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .slice(0, 60);
  return `${slug === '' ? `velorki-${id}` : slug}.gpx`;
}
