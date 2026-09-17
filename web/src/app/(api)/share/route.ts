// SPDX-License-Identifier: AGPL-3.0-only
import { z } from 'zod';
import { json, withApi } from '@/server/api';
import { SHARE_BODY_LIMIT, readJsonBody } from '@/server/body';
import { ApiError } from '@/server/errors';
import { requireEntitlement } from '@/server/entitlement';
import { LIMITS, enforce } from '@/server/ratelimit';
import { getConfig, getCounters, getEntitlement, getStore } from '@/server/singletons';

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

export const POST = withApi(async (request, ctx) => {
  const config = getConfig();
  // The 2 MB GPX plus JSON escaping overhead; the exact limit is the schema's.
  const raw = await readJsonBody(request, SHARE_BODY_LIMIT);
  const appUserId = await requireEntitlement(getEntitlement(), request.headers, ctx.log);
  await enforce(getCounters(), appUserId, [LIMITS.sharePerDay], ctx.log);

  const parsed = shareBodySchema.safeParse(raw);
  if (!parsed.success) {
    throw new ApiError(
      'invalid_request',
      parsed.error.issues.map((i) => `${i.path.join('.') || '(body)'}: ${i.message}`).join('; '),
    );
  }

  // Nothing links a share row to the rider who created it: the share id is the
  // only capability, and the store holds no account identifier.
  const record = getStore().create(parsed.data);
  ctx.log.info({ shareId: record.id, kind: record.kind }, 'share created');

  return json({ id: record.id, url: `${config.PUBLIC_BASE_URL}/s/${record.id}` }, 201);
});
