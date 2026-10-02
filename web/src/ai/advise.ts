// SPDX-License-Identifier: AGPL-3.0-only
import type { LanguageModel } from 'ai';
import { describeSummary } from './describe';
import { PlanToolError, runForcedTool, type LlmUsage } from './plan';
import { adviseRouteSchema, type AdviseRoute, type PlanRequest } from './schema';

export interface AdviseResult {
  advice: AdviseRoute;
  usage: LlmUsage;
  model: string;
}

/**
 * How far past the route's length a kilometre mark may lie and still count
 * as on the route: the digest's marks are rounded to two decimals.
 */
const KM_SLACK = 0.05;

/**
 * Build the user turn for the `route` step: the rider's question, then the
 * route as the description step reads it, digest and positions included,
 * every figure in the rider's units.
 */
export function buildAdvisePrompt(body: PlanRequest): string {
  const lines = [`Rider question: ${body.prompt}`, `Units: ${body.units}`, `Locale: ${body.locale}`];
  const summary = body.route_summary;
  if (summary !== undefined) {
    lines.push(...describeSummary(summary, body.units));
    // The tool counts in kilometres whatever the rider reads.
    lines.push(
      `For the tool: the route is ${summary.distance_km.toFixed(2)} km long, ` +
        'and from_km and to_km are kilometres from its start.',
    );
  }
  return lines.join('\n');
}

/**
 * Rejects advice the schema accepts but the request does not: a place id
 * that is not in the request's digest, a kilometre mark off the route, a
 * stretch that ends before it starts. Such an answer is a miss and asked for
 * again, like an answer without the tool call.
 */
export function checkAdvice(advice: AdviseRoute, body: PlanRequest): void {
  const summary = body.route_summary;
  const length = summary?.distance_km ?? 0;
  const ids = new Set((summary?.digest?.places ?? []).map((p) => p.id));
  const problems: string[] = [];

  const km = (value: number | undefined, where: string): void => {
    if (value === undefined) return;
    if (value < 0 || value > length + KM_SLACK) {
      problems.push(`${where} ${String(value)} is not on the route (0 to ${String(length)} km)`);
    }
  };
  const range = (from: number | undefined, to: number | undefined, where: string): void => {
    km(from, `${where}.from_km`);
    km(to, `${where}.to_km`);
    if (from !== undefined && to !== undefined && to < from) {
      problems.push(`${where} ends before it starts`);
    }
  };
  const place = (id: string | undefined, where: string): void => {
    if (id !== undefined && !ids.has(id)) problems.push(`${where} ${id} is not a place of the digest`);
  };

  advice.findings.forEach((finding, i) => {
    const where = `findings.${String(i)}`;
    range(finding.from_km, finding.to_km, where);
    place(finding.place_id, `${where}.place_id`);
    const fix = finding.fix;
    if (fix?.type === 'add_stop') place(fix.place_id, `${where}.fix.place_id`);
    if (fix?.type === 'avoid') range(fix.from_km, fix.to_km, `${where}.fix`);
  });

  if (problems.length > 0) {
    throw new PlanToolError(`The route advice was not usable: ${problems.join('; ')}`);
  }
}

/**
 * Run the `route` step: a non-streaming call forced to answer with a single
 * `advise_route` tool call, checked against the request's digest.
 */
export async function runAdvise(opts: {
  model: LanguageModel;
  system: string;
  body: PlanRequest;
  abortSignal?: AbortSignal;
}): Promise<AdviseResult> {
  const result = await runForcedTool({
    model: opts.model,
    system: opts.system,
    prompt: buildAdvisePrompt(opts.body),
    toolName: 'advise_route',
    description:
      "Answer the rider's question about the route and list a few concrete findings. Call this exactly once.",
    schema: adviseRouteSchema,
    unusable: 'The route advice was not usable',
    missing: 'The model did not answer about the route.',
    check: (advice) => {
      checkAdvice(advice, opts.body);
    },
    ...(opts.abortSignal === undefined ? {} : { abortSignal: opts.abortSignal }),
  });
  return { advice: result.value, usage: result.usage, model: result.model };
}
