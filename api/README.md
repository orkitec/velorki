# Velorki API

The relay service behind the Velorki bike app.

Velorki is open source, which means its APK cannot hold any secrets. This
service is the small piece that has to be trusted: it keeps the Strava and Ride
with GPS client secrets, the RevenueCat secret key and the LLM API key, and it
hands the app back only what the app is allowed to have. It stores as little as
possible — no accounts, no rides, no tokens; the only thing it persists is a
GPX file someone explicitly chose to share.

- **Stack:** Fastify 5, zod, pino, the Vercel AI SDK with an OpenAI-compatible
  provider, `node:sqlite`, TypeScript (ESM, NodeNext).
- **Runtime:** stock Node 22.13+ (`node:sqlite` is unflagged from there; developed on Node 26). No native addons, no
  compiled dependencies, no packages with install scripts. `npm run check:deps`
  enforces this.
- **Licence:** AGPL-3.0-only, see [LICENSE](./LICENSE).

The full HTTP contract lives in [openapi.yaml](./openapi.yaml).

## What it does

| Route | Purpose |
| --- | --- |
| `GET /health` | Liveness, build version, BRouter reachability, LLM configuration. No auth. |
| `POST /oauth/strava/token` · `/refresh` | Adds the Strava client secret to the token exchange and passes Strava's answer through unchanged. |
| `POST /oauth/rwgps/token` | Same for Ride with GPS. `/oauth/rwgps/refresh` answers 501: RwGPS tokens do not expire. |
| `POST /ai/plan` | Server-Sent Events. `step=plan` turns a rider's sentence into structured routing parameters via one forced tool call; `step=describe` streams a short prose description of a computed route. |
| `POST /share` | Stores a GPX plus a summary and returns a public link. |
| `GET /s/:id` · `/s/:id.gpx` | The public share page and the raw GPX. No auth. |

Everything under `/oauth/*`, `/ai/*` and `POST /share` requires
`Authorization: Bearer <revenuecat_app_user_id>` and an active entitlement.

### Conventions

- Errors always look like
  `{"error": {"code": "...", "message": "...", "retry_after_s": 30}}`.
  Codes: `invalid_request` (400), `not_entitled` (401), `consent_required`
  (403), `not_found` (404), `rate_limited` (429), `upstream_error` (502),
  `unavailable` (503).
- `X-Request-Id` is echoed when supplied and generated otherwise; it appears on
  every response and in every log line for that request.
- `X-Velorki-Client` (e.g. `android/1.0.0+1`) is logged when present.
- Rate limits are in-memory token buckets in a single process. A 429 carries
  both `retry_after_s` in the body and a `Retry-After` header.

### Privacy notes

These are deliberate, and worth keeping that way in a fork:

- `POST /ai/plan` requires `X-AI-Consent: 1` on **every** request. There is no
  server-side memory of consent.
- The prompt sent to the model never contains the `app_user_id`, and start
  coordinates are rounded to two decimals (~1 km) server-side as well as in the
  app.
- Share rows carry no link to the rider who created them. The 10-character id
  is the only capability, and rows expire after 365 days.
- Tokens and secrets are never logged; `authorization` and `cookie` headers are
  redacted in the pino config, and upstream error messages are scrubbed of the
  client secret before being echoed.

## Configuration

All configuration comes from the environment. See [.env.example](./.env.example)
for the complete, documented list.

Missing integrations degrade rather than crash the service:

| Missing | Effect |
| --- | --- |
| `STRAVA_CLIENT_ID` / `STRAVA_CLIENT_SECRET` | `/oauth/strava/*` → 503 `unavailable` |
| `RWGPS_CLIENT_ID` / `RWGPS_CLIENT_SECRET` | `/oauth/rwgps/*` → 503 `unavailable` |
| `LLM_BASE_URL` / `LLM_MODEL` | `/ai/plan` → 503, `/health` reports `llm: "unconfigured"` |
| `BROUTER_URL` | `/health` reports `brouter: "unconfigured"` |
| `REVENUECAT_SECRET_KEY` (in live mode) | every authenticated route → 503 `unavailable` |

`REVENUECAT_MODE=stub` makes everyone entitled. That is the right setting for a
fork or for local development, and the wrong one for anything public.

## Running it

```sh
npm install
cp .env.example .env   # then fill in what you need
npm run dev            # tsx watch, reloads on change
```

The dev server reads `.env` only if you load it yourself (e.g. `node --env-file=.env`);
in production the environment is already set.

| Script | What it does |
| --- | --- |
| `npm run dev` | `tsx watch src/server.ts` |
| `npm run build` | `tsc` to `dist/`, then copies the system prompts |
| `npm start` | `node dist/server.js` |
| `npm run lint` | ESLint (flat config, typescript-eslint, type-checked rules) |
| `npm run typecheck` | `tsc --noEmit` |
| `npm test` | Vitest; upstreams are mocked, nothing touches the network |
| `npm run check:deps` | Fails if any runtime dependency has a `binding.gyp` or an install script |

## Deployment (Orkify)

`orkify` runs `npm run build` and then `node dist/server.js`.

- Entry point: `dist/server.js`.
- Configuration: `process.env` only.
- Listens on `PORT` (default 8080), binds `HOST` (default `0.0.0.0`).
- Health check path: `GET /health` — unauthenticated, returns 200 with
  `{"status":"ok"}` as long as the process is up. `brouter` and `llm` in that
  body describe integrations, not liveness; do not fail the deploy on them.
- Graceful shutdown: SIGTERM closes the server, drains in-flight requests and
  exits 0, with a 10 s hard deadline. SIGINT behaves the same.
- `SHARE_DB_PATH` must point at a **persistent volume**. On ephemeral storage
  every deploy silently breaks every share link that was handed out.
- Set `TRUST_PROXY=1` only when a proxy you control terminates the connection.

**Keep this service free of native dependencies.** No `node-gyp`, no
`better-sqlite3`, no `sharp`, no packages with install scripts: it must stay a
plain `node dist/server.js` on a stock runtime, which is also what makes it
cheap for someone to self-host a fork. `npm run check:deps` is the guard; run it
in CI.

## Layout

```
src/
  server.ts          process entry: boot, listen, graceful shutdown
  app.ts             buildApp() - the Fastify instance, also used by the tests
  config.ts          zod-validated environment
  plugins/           requestid, errors, ratelimit, entitlement
  routes/            health, oauth, ai, share
  ai/                provider (the single getModel switch point), plan,
                     describe, schema, prompts/*.md
  share/             sqlite store, public HTML page
  util/              lru, tokenbucket, sse
test/                vitest suites, all upstreams mocked
```

The system prompts are plain Markdown in `src/ai/prompts/`, versioned by
filename (`plan.v1.md`), loaded once at startup and copied into `dist/` by the
build. Editing them needs no code change.
