# Cloudflare Pages: app.velorki.com

The Pages project `velorki-app` serves the Flutter web build
(`flutter build web --wasm --no-web-resources-cdn` in `app/`, after
`tool/web_assets.sh`; output `app/build/web`) and, through a
Pages Function, the tile mirror under the same origin, so the app fetches
tiles without CORS.

- `pages/wrangler.toml`: the project config.
- `pages/functions/tiles/[[path]].js`: the function on `/tiles/*`; the logic
  is in `pages/tiles_proxy.mjs`.
- `app/web/_headers` ships with the build: cross-origin isolation
  (COOP/COEP `credentialless`), the Content-Security-Policy (every host the
  app loads from, named there), `nosniff`, referrer policy and cache rules
  for the static files. The engine and maplibre-gl-js are served from the
  site itself, so a build with the CDN default is refused by that policy.

## /tiles

| Request | Origin |
| --- | --- |
| `GET /tiles/latest.json` | `raw.githubusercontent.com/orkitec/velorki-data/main/latest.json`, every `baseUrl` rewritten to `<origin>/tiles/<tag>/`, five minutes' cache |
| `GET`/`HEAD /tiles/<tag>/<TILE>.rd5`, `.gaz`, `manifest.json` | `github.com/orkitec/velorki-data/releases/download/<tag>/<file>`, redirect followed, streamed, cached a year as immutable |

`<tag>` is `tiles-YYYYMMDD` or `tiles-YYYYMMDD-sN`, `<TILE>` like `E5_N45` or
`W120_S35`. Full responses are kept in the edge cache (`caches.default`, which
only works on the custom domain, not on `*.pages.dev`); `Range` requests go to
the origin and are not cached. Only `Range` is forwarded. Anything else under
`/tiles/` is a 404; methods other than GET, HEAD and OPTIONS a 405.

Tests (Node's built-in runner, no dependencies):

    node --test deploy/cloudflare/test/*.test.mjs

A `v*` release deploys it (`release.yml`, job `web`, after approval in the
`release` environment). By hand, from `deploy/cloudflare/pages/`, after
`app/tool/web_assets.sh` and the build: `npx wrangler pages deploy`.

## One-time setup

1. Cloudflare → Workers & Pages → Create → Pages → Direct Upload, project
   name `velorki-app`.
2. In the project, Custom domains → add `app.velorki.com` (the zone is on the
   same Cloudflare account, so the DNS record is created there).
3. My Profile → API Tokens → Create a custom token with only
   *Account → Cloudflare Pages → Edit*, for this account. Note the Account ID
   (Workers & Pages overview, right column).
4. GitHub → Settings → Environments → `release`: secret
   `CLOUDFLARE_API_TOKEN` and secret `CLOUDFLARE_ACCOUNT_ID`. Until both are
   set, the `web` job of `release.yml` builds and uploads nothing.
5. GitHub → Settings → Actions → General: add `cloudflare/wrangler-action@*`
   to the allowed actions, or a run using it ends in `startup_failure`.

## Trying it locally

From `app/`: `flutter build web --wasm --no-web-resources-cdn --dart-define-from-file=env/web.json`,
then `python3 tool/web_serve.py` and open http://localhost:8080 in Chrome. The
script sends the build's `_headers` and stands in for the tiles function: the
pointer comes from velorki-data, tiles are fetched from the GitHub releases and
kept in `build/web_tile_cache`.
