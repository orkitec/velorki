// SPDX-License-Identifier: AGPL-3.0-only
import { streamText, type LanguageModel } from 'ai';
import type { PlanRequest, RouteDigest } from './schema';
import { modelId, type LlmUsage } from './plan';

export type Units = PlanRequest['units'];
type RouteSummary = NonNullable<PlanRequest['route_summary']>;

const MI_PER_KM = 0.621371;
const FT_PER_M = 3.28084;

/** A distance along the route, in the rider's units, to one decimal. */
function distance(km: number, units: Units): string {
  return units === 'imperial' ? `${(km * MI_PER_KM).toFixed(1)} mi` : `${km.toFixed(1)} km`;
}

/** A height or a short distance, in the rider's units, whole. */
function height(m: number, units: Units): string {
  return units === 'imperial'
    ? `${String(Math.round(m * FT_PER_M))} ft`
    : `${String(Math.round(m))} m`;
}

function grade(percent: number): string {
  const rounded = Math.round(percent * 10) / 10;
  return `${rounded > 0 ? '+' : ''}${String(rounded)}%`;
}

/** A name from the gazetteer or the rider, kept to one line of the prompt. */
function oneLine(text: string): string {
  return text.replace(/[\p{Cc}\p{Zl}\p{Zp}]+/gu, ' ').trim();
}

/**
 * The digest as a few compact lines per section. Every figure is in the
 * rider's units. Positions go along to four decimals (about 11 m), which is
 * enough for the model to know the area it is describing.
 */
/** A position as the model reads it, to four decimals. */
function at(point: { lat: number; lon: number }): string {
  return `${point.lat.toFixed(4)}, ${point.lon.toFixed(4)}`;
}

function describeDigest(digest: RouteDigest, units: Units): string[] {
  const lines: string[] = [];
  if (digest.profile !== undefined) lines.push(`Bike profile: ${digest.profile}`);
  lines.push(`Loop: ${digest.loop ? 'yes, ends where it starts' : 'no'}`);

  if (digest.stretches.length > 0) {
    lines.push(
      'Stretches (from-to along the route: road, surface, average gradient, steepest; start position):',
    );
    for (const s of digest.stretches) {
      lines.push(
        `- ${distance(s.from_km, units)}-${distance(s.to_km, units)}: ${s.road}, ${s.surface}, ` +
          `${grade(s.avg_grade)}, steepest ${grade(s.max_grade)}; ${at(s.start)}`,
      );
    }
  }
  if (digest.climbs.length > 0) {
    lines.push('Climbs (start along the route: length, gain, average gradient, steepest):');
    for (const c of digest.climbs) {
      lines.push(
        `- ${distance(c.start_km, units)}: ${distance(c.length_km, units)}, ` +
          `${height(c.gain_m, units)} up, ${grade(c.avg_grade)}, steepest ${grade(c.max_grade)}`,
      );
    }
  }
  if (digest.towns.length > 0) {
    lines.push('Settlements passed (where along the route; position):');
    for (const t of digest.towns) {
      lines.push(`- ${distance(t.km, units)}: ${oneLine(t.name)} (${t.kind}); ${at(t)}`);
    }
  }
  if (digest.places.length > 0) {
    lines.push(
      'Places to stop near the route (id, where along the route, kind, name, how far off; position):',
    );
    for (const p of digest.places) {
      const name = p.name === undefined || oneLine(p.name) === '' ? 'unnamed' : oneLine(p.name);
      lines.push(
        `- ${p.id} at ${distance(p.km, units)}: ${p.kind}, ${name}, ${height(p.off_m, units)} off; ${at(p)}`,
      );
    }
  }
  return lines;
}

/** Build the user turn for the description step from the computed route. */
export function buildDescribePrompt(body: PlanRequest): string {
  const lines = [`Rider request: ${body.prompt}`, `Units: ${body.units}`, `Locale: ${body.locale}`];
  if (body.route_summary !== undefined) {
    lines.push(...describeSummary(body.route_summary, body.units));
  }
  return lines.join('\n');
}

/**
 * The route summary as prompt lines: the totals, the waypoint names and the
 * digest, every figure in the rider's units. Shared by every step that is
 * about a computed route.
 */
export function describeSummary(summary: RouteSummary, units: Units): string[] {
  const lines = [
    `Distance: ${distance(summary.distance_km, units)}`,
    `Total ascent: ${height(summary.ascent_m, units)}`,
    `Surface mix: ${describeSurface(summary.surface)}`,
  ];
  if (summary.waypoints && summary.waypoints.length > 0) {
    lines.push(`Waypoints: ${summary.waypoints.map(oneLine).join(', ')}`);
  }
  if (summary.highlights && summary.highlights.length > 0) {
    lines.push(`Highlights: ${summary.highlights.map(oneLine).join(', ')}`);
  }
  if (summary.digest !== undefined) {
    lines.push(...describeDigest(summary.digest, units));
  }
  return lines;
}

function describeSurface(surface: { paved?: number; gravel?: number; unpaved?: number }): string {
  const parts: string[] = [];
  for (const key of ['paved', 'gravel', 'unpaved'] as const) {
    const share = surface[key];
    if (share !== undefined) parts.push(`${Math.round(share * 100)}% ${key}`);
  }
  return parts.length > 0 ? parts.join(', ') : 'unknown';
}

/**
 * Run the description step, pushing each text delta to `onDelta` as it
 * arrives. Returns the usage once the stream is done.
 */
export async function runDescribe(opts: {
  model: LanguageModel;
  system: string;
  body: PlanRequest;
  onDelta: (delta: string) => void;
  abortSignal?: AbortSignal;
}): Promise<{ usage: LlmUsage; model: string; text: string }> {
  const result = streamText({
    model: opts.model,
    system: opts.system,
    prompt: buildDescribePrompt(opts.body),
    ...(opts.abortSignal === undefined ? {} : { abortSignal: opts.abortSignal }),
  });

  let text = '';
  for await (const delta of result.textStream) {
    if (delta === '') continue;
    text += delta;
    opts.onDelta(delta);
  }

  const usage = await result.totalUsage;
  return {
    usage: { in: usage.inputTokens ?? 0, out: usage.outputTokens ?? 0 },
    model: modelId(opts.model),
    text,
  };
}
