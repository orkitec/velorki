// SPDX-License-Identifier: AGPL-3.0-only
import { streamText, type LanguageModel } from 'ai';
import type { PlanRequest } from './schema';
import { modelId, type LlmUsage } from './plan';

/** Build the user turn for the description step from the computed route. */
export function buildDescribePrompt(body: PlanRequest): string {
  const summary = body.route_summary;
  const lines = [`Rider request: ${body.prompt}`, `Units: ${body.units}`, `Locale: ${body.locale}`];

  if (summary !== undefined) {
    lines.push(
      `Distance: ${summary.distance_km} km`,
      `Total ascent: ${summary.ascent_m} m`,
      `Surface mix: ${describeSurface(summary.surface)}`,
    );
    if (summary.waypoints && summary.waypoints.length > 0) {
      lines.push(`Waypoints: ${summary.waypoints.join(', ')}`);
    }
    if (summary.highlights && summary.highlights.length > 0) {
      lines.push(`Highlights: ${summary.highlights.join(', ')}`);
    }
  }

  return lines.join('\n');
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
