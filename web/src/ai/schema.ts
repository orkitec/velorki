// SPDX-License-Identifier: AGPL-3.0-only
import { z } from 'zod';

/**
 * Request and tool schemas for POST /ai/plan.
 *
 * Everything the client sends is validated here; nothing else in the AI path
 * trusts the request body.
 */

/** Loose BCP47 check: a language subtag plus optional script/region/variant subtags. */
const localeSchema = z
  .string()
  .trim()
  .min(2)
  .max(35)
  .regex(/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/, 'must be a BCP47 language tag')
  .default('en');

const latSchema = z.number().min(-90).max(90);
const lonSchema = z.number().min(-180).max(180);

/**
 * Coordinates are rounded to two decimals (~1.1 km) before they reach the
 * model. The app already does this; we repeat it server-side so a modified or
 * third-party client cannot leak a precise home location into the prompt.
 */
function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

const startSchema = z
  .object({ lat: latSchema, lon: lonSchema })
  .transform((s) => ({ lat: round2(s.lat), lon: round2(s.lon) }));

const contextSchema = z.object({
  start: startSchema.optional(),
  start_label: z.string().trim().max(120).optional(),
  today: z.string().trim().max(40).optional(),
});

const surfaceMixSchema = z.object({
  paved: z.number().min(0).max(1).optional(),
  gravel: z.number().min(0).max(1).optional(),
  unpaved: z.number().min(0).max(1).optional(),
});

/*
 * The route digest the app builds on the phone for `step=describe`: what the
 * route runs over, where it climbs, the settlements it passes and the places
 * to stop beside it. Optional, so app versions that never send one keep
 * working. Distances are kilometres along the route, gradients percent.
 *
 * The coordinates are validated but never rendered into the prompt: the model
 * reads names and kilometres, not the track.
 */

/** A kilometre mark along the route. */
const kmSchema = z.number().min(0).max(10_000);
/** A gradient in percent, signed; steeper than 60 % is not a road. */
const gradeSchema = z.number().min(-60).max(60);
/** A short OSM tag value such as `cycleway` or `asphalt`. */
const tagValueSchema = z
  .string()
  .trim()
  .min(1)
  .max(32)
  .regex(/^[a-z0-9_:;.-]+$/, 'must be an OSM tag value');
const pointSchema = z.object({ lat: latSchema, lon: lonSchema });

const stretchSchema = z.object({
  from_km: kmSchema,
  to_km: kmSchema,
  road: tagValueSchema,
  surface: tagValueSchema,
  avg_grade: gradeSchema,
  max_grade: gradeSchema,
  start: pointSchema,
  end: pointSchema,
});

const climbSchema = z.object({
  start_km: kmSchema,
  length_km: z.number().min(0).max(1_000),
  gain_m: z.number().min(0).max(10_000),
  avg_grade: gradeSchema,
  max_grade: gradeSchema,
});

const townSchema = z.object({
  name: z.string().trim().min(1).max(120),
  kind: z.enum(['city', 'town', 'village']),
  km: kmSchema,
  lat: latSchema,
  lon: lonSchema,
});

const placeSchema = z.object({
  id: z.string().regex(/^p[0-9]{1,3}$/, 'must look like p12'),
  kind: z.enum([
    'cafe',
    'bakery',
    'drinking_water',
    'toilets',
    'viewpoint',
    'water',
    'beach',
    'bicycle_shop',
    'bicycle_repair_station',
    'station',
  ]),
  name: z.string().trim().max(120).optional(),
  km: kmSchema,
  off_m: z.number().min(0).max(1_000),
  lat: latSchema,
  lon: lonSchema,
});

export const routeDigestSchema = z.object({
  profile: z.string().trim().max(20).optional(),
  loop: z.boolean(),
  stretches: z.array(stretchSchema).max(60).default([]),
  climbs: z.array(climbSchema).max(20).default([]),
  towns: z.array(townSchema).max(30).default([]),
  places: z.array(placeSchema).max(40).default([]),
});

export type RouteDigest = z.infer<typeof routeDigestSchema>;

const routeSummarySchema = z.object({
  distance_km: z.number().min(0).max(10_000),
  ascent_m: z.number().min(0).max(100_000),
  surface: surfaceMixSchema,
  waypoints: z.array(z.string().trim().max(120)).max(50).optional(),
  highlights: z.array(z.string().trim().max(200)).max(20).optional(),
  digest: routeDigestSchema.optional(),
});

export const planRequestSchema = z
  .object({
    step: z.enum(['plan', 'describe']),
    locale: localeSchema,
    units: z.enum(['metric', 'imperial']).default('metric'),
    prompt: z.string().trim().min(1).max(1000),
    context: contextSchema.optional(),
    route_summary: routeSummarySchema.optional(),
  })
  .superRefine((value, ctx) => {
    // There is nothing to describe without a summary of the computed route.
    if (value.step === 'describe' && value.route_summary === undefined) {
      ctx.addIssue({
        code: 'custom',
        path: ['route_summary'],
        message: 'route_summary is required when step is "describe"',
      });
    }
  });

export type PlanRequest = z.infer<typeof planRequestSchema>;

/**
 * The single tool the planning step may call. The shape is the contract
 * between the model and the app's router: the app turns these fields into a
 * BRouter query, so every field must be machine-usable.
 *
 * Fields with defaults stay optional in the generated JSON Schema, which keeps
 * weaker models from failing the call over a field they had nothing to say
 * about.
 */
export const proposeRouteSchema = z.object({
  distance_km: z
    .number()
    .min(5)
    .max(300)
    .describe('Target ride length in kilometres, 5 to 300.'),
  loop: z.boolean().describe('True when the ride should return to its start.'),
  start: z
    .object({
      use_current: z
        .boolean()
        .describe("True when the ride starts at the rider's current position."),
      name: z
        .string()
        .max(120)
        .optional()
        .describe('Name of the starting place, only when use_current is false.'),
    })
    .describe('Where the ride begins.'),
  via: z
    .array(z.string().max(120))
    .max(4)
    .default([])
    .describe('Up to 4 place names the rider explicitly asked to pass through.'),
  surface: z.enum(['paved', 'mixed', 'gravel']).describe('Preferred road surface.'),
  hills: z.enum(['avoid', 'neutral', 'seek']).describe('Attitude towards climbing.'),
  traffic_tolerance: z.enum(['low', 'medium', 'high']).describe('Tolerance for motor traffic.'),
  stops: z
    .array(z.enum(['cafe', 'bakery', 'viewpoint', 'lake', 'water', 'none']))
    .default(['none'])
    .describe('Kinds of stop the rider would like along the way.'),
  profile_hint: z
    .enum(['trekking', 'fastbike', 'mtb', 'gravel'])
    .describe('Routing profile that best matches the request.'),
  notes: z
    .string()
    .max(200)
    .default('')
    .describe("One short sentence for the rider, in the rider's locale."),
  confidence: z
    .number()
    .min(0)
    .max(1)
    .default(0.5)
    .describe('How confident you are that this matches the request.'),
});

export type ProposeRoute = z.infer<typeof proposeRouteSchema>;
