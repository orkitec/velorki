// SPDX-License-Identifier: AGPL-3.0-only
import {
  generateText,
  InvalidToolInputError,
  NoSuchToolError,
  tool,
  ToolChoiceViolationError,
  type LanguageModel,
} from 'ai';
import type { z } from 'zod';
import type { PlanRequest } from './schema';
import { proposeRouteSchema, type ProposeRoute } from './schema';

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

/** How many times a planning call is made before its failure is reported. */
export const PLAN_ATTEMPTS = 2;

/** Whether [err] is a model answering beside the tool, which is worth a retry. */
function isMissedAnswer(err: unknown): boolean {
  return (
    err instanceof PlanToolError ||
    ToolChoiceViolationError.isInstance(err) ||
    InvalidToolInputError.isInstance(err) ||
    NoSuchToolError.isInstance(err)
  );
}

/**
 * Run the planning step: a non-streaming call that is forced to answer with a
 * single `propose_route` tool call.
 */
export async function runPlan(opts: {
  model: LanguageModel;
  system: string;
  body: PlanRequest;
  abortSignal?: AbortSignal;
}): Promise<PlanResult> {
  const result = await runForcedTool({
    model: opts.model,
    system: opts.system,
    prompt: buildPlanPrompt(opts.body),
    toolName: 'propose_route',
    description:
      'Propose one concrete bike route matching the rider request. Call this exactly once.',
    schema: proposeRouteSchema,
    unusable: 'The proposed route was not usable',
    missing: 'The model did not propose a route.',
    ...(opts.abortSignal === undefined ? {} : { abortSignal: opts.abortSignal }),
  });
  return { route: result.value, usage: result.usage, model: result.model };
}

/**
 * One forced tool call, asked for again once when the model misses it.
 *
 * Cheap models now and then answer in prose or with arguments the schema
 * rejects despite the forced tool choice, so such an answer is asked for once
 * more before the rider sees an error. [check] may reject arguments the
 * schema accepts but the request does not (an id the request never sent) by
 * throwing a [PlanToolError]; that counts as a miss too. The usage of every
 * attempt is counted.
 */
export async function runForcedTool<S extends z.ZodType>(opts: {
  model: LanguageModel;
  system: string;
  prompt: string;
  toolName: string;
  description: string;
  schema: S;
  /** The start of the message for arguments that fail [schema]. */
  unusable: string;
  /** The message for an answer without the tool call. */
  missing: string;
  check?: (value: z.output<S>) => void;
  abortSignal?: AbortSignal;
}): Promise<{ value: z.output<S>; usage: LlmUsage; model: string }> {
  const spent: LlmUsage = { in: 0, out: 0 };
  for (let attempt = 1; ; attempt++) {
    try {
      const value = await attemptTool(opts, spent);
      return { value, usage: { ...spent }, model: modelId(opts.model) };
    } catch (err) {
      const retry =
        isMissedAnswer(err) && attempt < PLAN_ATTEMPTS && opts.abortSignal?.aborted !== true;
      if (!retry) throw err;
    }
  }
}

/**
 * One forced call. The tool has no `execute`: the AI SDK therefore stops
 * after the call and hands us the arguments, which is exactly what the app
 * needs. Adds what the call cost to `spent` when it answered at all.
 */
async function attemptTool<S extends z.ZodType>(
  opts: {
    model: LanguageModel;
    system: string;
    prompt: string;
    toolName: string;
    description: string;
    schema: S;
    unusable: string;
    missing: string;
    check?: (value: z.output<S>) => void;
    abortSignal?: AbortSignal;
  },
  spent: LlmUsage,
): Promise<z.output<S>> {
  const result = await generateText({
    model: opts.model,
    system: opts.system,
    prompt: opts.prompt,
    toolChoice: 'required',
    tools: {
      [opts.toolName]: tool({ description: opts.description, inputSchema: opts.schema }),
    },
    ...(opts.abortSignal === undefined ? {} : { abortSignal: opts.abortSignal }),
  });
  spent.in += result.totalUsage.inputTokens ?? 0;
  spent.out += result.totalUsage.outputTokens ?? 0;

  const call = result.toolCalls.find((c) => c.toolName === opts.toolName);
  if (call === undefined) {
    throw new PlanToolError(opts.missing);
  }

  // Belt and braces: the SDK validates the tool input against the same schema,
  // but re-parsing here applies the defaults and guarantees the shape of what
  // we put on the wire even if a future SDK version relaxes its validation.
  const parsed = opts.schema.safeParse(call.input);
  if (!parsed.success) {
    throw new PlanToolError(
      `${opts.unusable}: ${parsed.error.issues
        .map((i) => `${i.path.join('.')} ${i.message}`)
        .join('; ')}`,
    );
  }
  opts.check?.(parsed.data);
  return parsed.data;
}
