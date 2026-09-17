# Velorki web

`velorki.com` and `api.velorki.com` in one Next.js app: the public website, the
share pages, and the relay service behind the Velorki bike app.

Velorki is open source, which means its APK cannot hold any secrets. The relay
is the small piece that has to be trusted: it keeps the Strava and Ride with GPS
client secrets, the RevenueCat secret key and the LLM API key, and hands the app
back only what the app is allowed to have. It stores as little as possible - no
accounts, no rides, no tokens; the only thing it persists is a GPX file someone
explicitly chose to share.

- **Stack:** Next.js 16 (App Router, standalone output), TypeScript, zod, pino,
  the Vercel AI SDK with an OpenAI-compatible provider, `node:sqlite`,
  `@orkify/cache` for cross-worker state, next-intl, MapLibre GL.
- **Runtime:** stock Node 22.13+ (`node:sqlite` is unflagged from there). No
  native addons, no compiled dependencies, no packages with install scripts.
  `npm run check:deps` enforces this.
- **Licence:** AGPL-3.0-only, see [LICENSE](./LICENSE). Every `.ts`/`.tsx` file
  starts with `// SPDX-License-Identifier: AGPL-3.0-only`.

The full HTTP contract lives in [openapi.yaml](./openapi.yaml).

## Two hosts, one process

Host separation is strict and enforced before any handler runs, in
[`src/proxy.ts`](./src/proxy.ts):

| Host | Serves |
| --- | --- |
| `api.velorki.com` (`API_HOST`) | the API routes below, and nothing else |
| `velorki.com` (`SITE_HOST`) | the website, `/s/<id>`, `/s/<id>.gpx`, `/.well-known/*` |
| anything else | 404 `not_found`, so a stray DNS name cannot probe the service |

- An unknown `(method, path)` on the API host answers the Fastify-shaped JSON
  404 `No route for GET /nope?a=1.`
- `api.velorki.com/s/<id>` answers 308 to the site host: links handed out before
  the split keep working.
- A loopback `Host` (`localhost`, `127.0.0.1`, `::1`) is the API role in every
  mode, because Orkify's health probe calls `http://localhost:<port>/health`
  and cannot set a `Host` header. Caddy always forwards the public host and the
  origin only accepts Cloudflare, so nothing else arrives that way.
- Locally, `DEV_HOSTS=1` lets one origin play both roles: the API is at
  `api.localhost:3000`, under `/__api/*`, or with `X-Velorki-Host: api`; plain
  `localhost:3000` is the site.

## The relay

| Route | Purpose |
| --- | --- |
| `GET`/`HEAD` `/health` | Liveness, build version, BRouter reachability, LLM configuration. No auth. |
| `POST /oauth/strava/token` · `/refresh` | Adds the Strava client secret to the token exchange and passes Strava's answer through unchanged. |
| `POST /oauth/rwgps/token` | Same for Ride with GPS. `/oauth/rwgps/refresh` answers 501: RwGPS tokens do not expire. |
| `POST /ai/plan` | Server-Sent Events. `step=plan` turns a rider's sentence into structured routing parameters via one forced tool call; `step=describe` streams a short prose description of a computed route. |
| `POST /share` | Stores a GPX plus a summary and returns a public link on the site host. |
| `GET /s/<id>` · `/s/<id>.gpx` | The public share page and the raw GPX, on `velorki.com`. No auth. |

Everything under `/oauth/*`, `/ai/*` and `POST /share` requires
`Authorization: Bearer <revenuecat_app_user_id>` and an active entitlement.

### Conventions

- Errors always look like
  `{"error": {"code": "...", "message": "...", "retry_after_s": 30}}`.
  Codes: `invalid_request` (400), `not_entitled` (401), `consent_required`
  (403), `not_found` (404), `rate_limited` (429), `upstream_error` (502),
  `unavailable` (503).
- `X-Request-Id` is echoed when it is short and safe (≤128 chars, `[\w.:@/+-]`)
  and generated otherwise; it appears on every response and in every log line
  for that request.
- `X-Velorki-Client` (e.g. `android/1.0.0+1`) is logged when present.
- Every API-host response is `cache-control: no-store`, stamped by `withApi`
  on anything that does not bring its own policy - `POST /ai/plan` keeps the
  `no-cache, no-transform` an event stream needs. The proxy sets a policy only
  on the answers it produces itself. The share page is `public, max-age=300`
  and the GPX `public, max-age=3600`.
- Handler order is the Fastify one, with one addition in front: the per-IP
  rate limit → body → entitlement → consent → per-rider rate limit → handler.
  `POST /share` (60 per hour per IP) and `POST /ai/plan` (60 per hour per IP)
  charge that first limit before reading up to 3 MB and 1 MB respectively, so
  an unauthenticated caller cannot keep the workers buffering.

### Rate limits are fixed windows

The Fastify relay used per-process token buckets, which two cluster workers
cannot share. The numbers are unchanged; the shape is not. A limit of "10 per
minute" now allows 10 requests inside one wall-clock minute and resets at its
boundary, with no burst credit carried over, and `Retry-After` is the number of
seconds left in the window that rejected the request. The counters live in
`@orkify/cache`, so the 11th request in a minute is refused whichever worker
answers it.

The same `Counters` interface (`incr` / `get` / `set`, see
[`src/server/counters.ts`](./src/server/counters.ts)) carries the entitlement
cache (600 s entitled, 60 s not), the daily LLM spend and the share-sweep
election. Nothing in it has to survive a restart.

### Privacy notes

These are deliberate, and worth keeping that way in a fork:

- `POST /ai/plan` requires `X-AI-Consent: 1` on **every** request. There is no
  server-side memory of consent.
- The prompt sent to the model never contains the `app_user_id`, and start
  coordinates are rounded to two decimals (~1 km) server-side as well as in the
  app.
- Share rows carry no link to the rider who created them. The 10-character id
  is the only capability, and rows expire after 365 days.
- The share page is `noindex`, carries no third-party script source at all
  (MapLibre is bundled from npm) and loads only OpenFreeMap tiles.
- Tokens and secrets are never logged; `authorization` and `cookie` are
  redacted in the pino config, and upstream error messages are scrubbed of the
  client secret before being echoed.

## Configuration

All configuration comes from the environment. See [.env.example](./.env.example)
for the complete, documented list.

Missing integrations degrade rather than crash the app:

| Missing | Effect |
| --- | --- |
| `STRAVA_CLIENT_ID` / `STRAVA_CLIENT_SECRET` | `/oauth/strava/*` → 503 `unavailable` |
| `RWGPS_CLIENT_ID` / `RWGPS_CLIENT_SECRET` | `/oauth/rwgps/*` → 503 `unavailable` |
| `LLM_BASE_URL` / `LLM_MODEL` | `/ai/plan` → 503, `/health` reports `llm: "unconfigured"` |
| `BROUTER_URL` | `/health` reports `brouter: "unconfigured"` |
| `REVENUECAT_SECRET_KEY` (in live mode) | every authenticated route → 503 `unavailable` |
| `APPLE_TEAM_ID` | `/.well-known/apple-app-site-association` → 404 |
| `ANDROID_CERT_SHA256` | `/.well-known/assetlinks.json` → 404 |

`REVENUECAT_MODE=stub` makes everyone entitled. That is the right setting for a
fork or for local development, and the wrong one for anything public.

## Running it

```sh
npm install
cp .env.example .env.local   # then fill in what you need
npm run dev
```

A useful `.env.local` for development:

```sh
DEV_HOSTS=1
COUNTERS=memory
REVENUECAT_MODE=stub
SHARE_DB_PATH=./data/share.sqlite
PUBLIC_BASE_URL=http://localhost:3000
```

Then `http://localhost:3000/` is the site, `http://localhost:3000/__api/health`
(or `http://api.localhost:3000/health`) is the relay, and a share created
through `POST /__api/share` is readable at `http://localhost:3000/s/<id>`.

| Script | What it does |
| --- | --- |
| `npm run dev` | `next dev` |
| `npm run build` | `next build` (standalone) plus the asset copy |
| `npm start` | `node .next/standalone/server.js` |
| `npm run start:cluster` | `orkify run` with two workers on port 8080, the same flags the VPS uses, to see the shared counters work |
| `npm run lint` | ESLint (flat config, typescript-eslint, type-checked rules) |
| `npm run typecheck` | `tsc --noEmit` |
| `npm test` | Vitest; upstreams are mocked, nothing touches the network |
| `npm run check:deps` | Fails if any runtime dependency has a `binding.gyp` or an install script |
| `npm run locales` | Regenerates `src/i18n/locales.generated.ts` from `messages/*.json`; run it after adding a catalogue |

## Tests

`npm test` runs the whole suite in `test/`. Everything is handler level: a test
imports the route module and calls its exported `GET`/`POST` with a real
`Request`, so what is asserted is the same object the runtime produces.

| File | What it covers |
| --- | --- |
| `helpers.ts` | `withEnv()` installs a whole set of singletons - config from an explicit env map, `MemoryCounters`, a `:memory:` SQLite store, an injected model factory - and tears them down again. Also the mock language models, `parseSse()`, `sampleGpx()`, `revenueCatResponse()`. |
| `health.test.ts` | `/health` body, HEAD, the 60 s BRouter probe cache, request id echo/mint. |
| `oauth.test.ts` | Both providers: passthrough, allowlist, secret scrubbing, upstream failures, 501 for RwGPS refresh. |
| `entitlement.test.ts` | Bearer parsing, stub and live mode, positive/negative cache TTLs, "upstream failure is not cached as not entitled". |
| `ratelimit.test.ts` | The 429 through the HTTP layer, `Retry-After`, `CLIENT_IP_HEADER` keying, `clientIp()`. |
| `counters.test.ts` | `MemoryCounters` TTL semantics and the fixed window across **two** `Counters` consumers on one backend: the 11th call in a minute is denied whichever one makes it. |
| `share.test.ts` | Create, validate, rate limit, the GPX route and its headers, expiry, the store, the page's formatting. |
| `ai.test.ts` | Consent, budget, validation, the `route_request` / `text` / `done` / `error` events, coordinate rounding. |
| `body.test.ts` | `readJsonBody`: content-length, streamed limit with cancel, empty, non-JSON, wrong content type. |
| `sse.test.ts` | Headers, the `: open` preamble, `: ping` every 20 s under fake timers, abort on `request.signal` and on stream cancel. |
| `proxy.test.ts` | The host gate, the JSON 404 message, `/s/` id validation and the `.gpx` rewrite, the 308, request id, cache headers, `config.matcher`. Uses `next/experimental/testing/server`. |
| `prompts.test.ts` | Both system prompts load from `src/ai/prompts` without their SPDX header. |
| `wellknown.test.ts` | The association files, configured and unconfigured. |
| `contract/sse.test.ts` | Replays the three `text/event-stream` examples from `openapi.yaml` byte for byte. |
| `sharepage.test.tsx` | The page's markup and escaping, and `loadShare()`: live, unknown, malformed and expired ids. |

One thing the suite cannot assert is an HTTP status Next owns. After a change
to the share page or to the proxy's share branch, check it by hand against a
build:

```sh
npm run build
DEV_HOSTS=1 REVENUECAT_MODE=stub COUNTERS=memory npm start   # standalone reads
                                                             # no .env file
curl -so /dev/null -w '%{http_code}\n' http://localhost:3000/s/AbCdEf0123   # 404
```

An unknown or expired link has to be **404**, not a 200 carrying the "no longer
available" page: under `cacheComponents` the page streams a static shell before
its own `notFound()` runs, so the proxy settles it first.

## Layout

```
src/
  proxy.ts            host gate, request id, /s/* handling, next-intl
  instrumentation.ts  boot log, cache configure, share-sweep election
  config.ts hosts.ts  zod-validated environment; the API route table
  server/             api (the withApi wrapper), body, sse, counters,
                      ratelimit, entitlement, oauth, errors, log, requestid,
                      singletons
  ai/                 provider (the single getModel switch point), plan,
                      describe, schema, prompts/*.md
  share/              sqlite store, presentation helpers
  app/(api)/          health, oauth/*, ai/plan, share
  app/(share)/         the share document root, its not-found body, and
  app/(share)/s/[id]/  the share page, its map, and the gpx route
  app/(share)/s/gone/  the 404 the proxy rewrites a dead link to
  app/(site)/         the website, and the .well-known association files
test/                 vitest suites, all upstreams mocked
```

The system prompts are plain Markdown in `src/ai/prompts/`, versioned by
filename (`plan.v1.md`), read at runtime from `process.cwd()` and traced into
the standalone output by `outputFileTracingIncludes`. Editing them needs no code
change.

## Deployment

See `docs/DEPLOY_WEB.md` in the repository root for the VPS, Caddy, Cloudflare
and Orkify setup. The parts that matter here:

- Entry point `node .next/standalone/server.js`, configuration from
  `process.env` only, health check `GET /health`.
- `SHARE_DB_PATH` must point at a **persistent volume** outside the release
  tree. On ephemeral storage every deploy silently breaks every share link.
- `TRUST_PROXY=1` and `CLIENT_IP_HEADER=cf-connecting-ip` only when the origin
  is firewalled to the proxy that sets them. `CLIENT_IP_HEADER` is read only
  when `TRUST_PROXY=1`; without it every caller shares the key "unknown".
- Worker `0` runs the daily share sweep; the others do not.

**Keep this app free of native dependencies.** No `node-gyp`, no
`better-sqlite3`, no `sharp`, no packages with install scripts: it must stay a
plain `node server.js` on a stock runtime, which is also what makes it cheap for
someone to self-host a fork. `npm run check:deps` is the guard; run it in CI.

## Website

`velorki.com` itself: a marketing landing page, the end-user guide, the three
legal pages, and the download page. App Router pages under
`src/app/(site)/[locale]/`, Tailwind 4 for the styling, next-intl for the
locales, and everything the app's own look needs (Barlow Condensed, Manrope,
the four accents) taken from `app/lib/app/theme.dart`.

| Where | What |
| --- | --- |
| `src/app/(site)/[locale]/` | the pages: landing, `plus`, `download`, `docs/[[...slug]]`, `privacy`, `terms`, `imprint` |
| `content/<locale>/` | the Markdown behind `/docs` and the legal pages - see [content/README.md](./content/README.md) |
| `messages/<locale>.json` | the UI strings; `src/i18n/locales.generated.ts` lists the locales that exist |
| `src/components/` | header, footer, docs navigation, the phone frame, the appearance and locale switchers |
| `src/site/` | content loading, the Markdown pipeline, SEO helpers, the screenshot manifest |
| `public/screenshots/<mode>-<accent>/` | written by `app/tool/screenshots.sh`; a missing file renders as a labelled placeholder |

Pages are prerendered per locale. English is unprefixed (`localePrefix:
'as-needed'`), so `/docs` is English and `/de/docs` German; `src/site/paths.ts`
is the single place that knows that rule, and every canonical URL, hreflang and
Open Graph tag is built through it.

**Adding a docs page.** Write `content/en/docs/<slug>.md` with `title`,
`description` and `order` in the front matter, and finish it with a `## Related`
list. Nothing else: the route, the sidebar, the sitemap and the previous/next
links all come from the file. Commit the English file only - German arrives
through Crowdin. The house style and the front-matter reference are in
[content/README.md](./content/README.md).

**SEO artefacts**, all generated, none hand-maintained:

| Route | Source |
| --- | --- |
| `/sitemap.xml` | `src/app/sitemap.ts` - every page in every locale, with hreflang alternates |
| `/robots.txt` | `src/app/robots.ts` - `/s/` disallowed, the sitemap announced |
| `/llms.txt`, `/llms-full.txt` | `src/app/llms*.txt/route.ts` - the guide as one plain-text file for assistants |
| `/manifest.webmanifest` | `src/app/manifest.ts` |
| `/og-card`, `/de/og-card` | the Open Graph card, drawn per locale with `next/og` |
| JSON-LD | `src/site/jsonld.ts`: Organization, WebSite, MobileApplication, TechArticle, BreadcrumbList, FAQPage |

**Running just the site.** `npm run dev` and open `http://localhost:3000/`;
nothing on the site half needs an API key or a database. `next dev` sets
`DEV_HOSTS=1` by itself; a production build (`npm start`) needs it in the
environment to serve the site on localhost.

Translation workflow: [docs/LOCALISATION.md](../docs/LOCALISATION.md).
Deployment: [docs/DEPLOY_WEB.md](../docs/DEPLOY_WEB.md).
