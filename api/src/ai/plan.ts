// SPDX-License-Identifier: AGPL-3.0-only
import { generateText, tool, type LanguageModel } from 'ai';
import type { PlanRequest } from './schema.js';
import { proposeRouteSchema, type ProposeRoute } from './schema.js';

export interface LlmUsage {
  in: number;
  out: number;
}

export interface PlanResult {
  route: ProposeRoute;
  usage: LlmUsage;
  model: string;
}

export function modelId(model: LanguageModel): string {
  return typeof model === 'string' ? model : model.modelId;
}

/**
 * Build the user turn for the planning step.
 *
 * Note what is *not* here: the app_user_id. The prompt only ever contains the
 * rider's own words and the coarse context they chose to share.
 */
export function buildPlanPrompt(body: PlanRequest): string {
  const lines = [`Rider request: ${body.prompt}`, `Units: ${body.units}`, `Locale: ${body.locale}`];

  const ctx = body.context;
  if (ctx?.start !== undefined) {
    // Already rounded to 2 decimals by the request schema.
    lines.push(`Approximate start: ${ctx.start.lat.toFixed(2)}, ${ctx.start.lon.toFixed(2)}`);
  }
  if (ctx?.start_label !== undefined) lines.push(`Start is known to the rider as: ${ctx.start_label}`);
  if (ctx?.today !== undefined) lines.push(`Today: ${ctx.today}`);

  return lines.join('\n');
}

export class PlanToolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PlanToolError';
  }
}

/**
 * Run the planning step: one non-streaming call that is forced to answer with
 * a single `propose_route` tool call.
 *
 * The tool has no `execute`: the AI SDK therefore stops after the call and
 * hands us the arguments, which is exactly what the app needs.
 */
export async function runPlan(opts: {
  model: LanguageModel;
  system: string;
  body: PlanRequest;
  abortSignal?: AbortSignal;
}): Promise<PlanResult> {
  const result = await generateText({
    model: opts.model,
    system: opts.system,
    prompt: buildPlanPrompt(opts.body),
    toolChoice: 'required',
    tools: {
      propose_route: tool({
        description:
          'Propose one concrete bike route matching the rider request. Call this exactly once.',
        inputSchema: proposeRouteSchema,
      }),
    },
    ...(opts.abortSignal === undefined ? {} : { abortSignal: opts.abortSignal }),
  });

  const call = result.toolCalls.find((c) => c.toolName === 'propose_route');
  if (call === undefined) {
    throw new PlanToolError('The model did not propose a route.');
  }

  // Belt and braces: the SDK validates the tool input against the same schema,
  // but re-parsing here applies the defaults and guarantees the shape of what
  // we put on the wire even if a future SDK version relaxes its validation.
  const parsed = proposeRouteSchema.safeParse(call.input);
  if (!parsed.success) {
    throw new PlanToolError(
      `The proposed route was not usable: ${parsed.error.issues
        .map((i) => `${i.path.join('.')} ${i.message}`)
        .join('; ')}`,
    );
  }

  return {
    route: parsed.data,
    usage: {
      in: result.totalUsage.inputTokens ?? 0,
      out: result.totalUsage.outputTokens ?? 0,
    },
    model: modelId(opts.model),
  };
}
