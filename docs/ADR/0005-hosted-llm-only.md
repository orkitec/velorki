# 5. The assistant uses a hosted model only

Status: accepted, 2026-09-12.

## Context

The assistant turns a sentence like "a nice 60 km loop from here past the lake"
into a structured planning request. It is the one feature that genuinely needs a
language model: on-device from the OS, bundled, or hosted behind the relay.

## Decision

The assistant calls a hosted model through the relay's `POST /ai/plan`, behind
an OpenAI-compatible interface (Vercel AI SDK with `@ai-sdk/openai-compatible`,
`LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL`), so a self-hosted vLLM or Ollama
endpoint is a configuration change; `getModel()` is the single switch point.

Its job is narrow: one call with `tool_choice: required` on `propose_route`,
returning a strict schema of distance, shape, place names and preferences. **It
never returns coordinates and never routes** — the app geocodes the names
through Photon and routes itself.

## Alternatives considered

- **OS-provided on-device models** (Apple Foundation Models on iOS 26 and
  A17 Pro or newer, Gemini Nano on some Android devices) — deferred: coverage
  gaps would have forced the hosted path anyway. Revisit when they close.
- **Bundling a small model** — app size and device spread.
- **Letting the model plan the route directly** — models invent coordinates and
  POIs; routing quality is BRouter's job and is testable.

## Consequences

- The assistant needs the relay, so it is Plus and hidden without one.
- Apple 5.1.2(i) applies: one-time consent, start rounded to about 1 km, no
  identifiers in the prompt, revocable in settings.
- Cost is roughly 10⁻⁴–10⁻³ USD per plan, capped by per-user limits and an
  `LLM_DAILY_BUDGET_USD` circuit breaker.
- Strava data is never sent to the model; their terms forbid it.
