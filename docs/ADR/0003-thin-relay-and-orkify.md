# 3. A thin relay, deployed by Orkify

Status: accepted, 2026-09-12.

## Context

Two things cannot live in an open-source app binary: the Strava and RideWithGPS
OAuth client secrets (both need a confidential exchange; RideWithGPS has no
PKCE) and the model API key. Link sharing also needs somewhere to put the file.

## Decision

Build `api/` as a deliberately thin relay on Node 22 and TypeScript: OAuth token
exchange and refresh, the AI relay, share links, health. No accounts, no user
database. Tokens go back to the phone; uploads go phone → service directly. The
relay is AGPL-3.0-only, so a modified hosted relay must publish its source; the
HTTP boundary leaves the Apache-2.0 app unaffected.

Deploy it through **Orkify** as a plain Node process rather than a hand-rolled
Docker and SSH pipeline, and enforce a dependency rule: stock Node 22+, no
native addons, no Bun/Deno/edge-only packages — Fastify, zod, pino, the Vercel
AI SDK, built-in `fetch`, `node:sqlite`. CI fails on any dependency with a
`binding.gyp` or an install script.

## Alternatives considered

- **Proxying all Strava and RideWithGPS traffic** — would put every user's ride
  data on our server for no gain.
- **Client secrets in the app** — extractable; `strava_client` was dropped for
  expecting exactly that.
- **Serverless or edge functions** — SSE, the dependency rule and self-hosting
  by forks are simpler on a plain process; `better-sqlite3` is a native addon.

## Consequences

- Forks either run the relay with their own credentials or set
  `VELORKI_API_URL` empty and lose only the integrations and the AI; the
  Dockerfile and GHCR image stay maintained for those who prefer containers.
- The share-link SQLite file is the only server state worth backing up.
