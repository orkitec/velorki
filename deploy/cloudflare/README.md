# Cloudflare Pages: app.velorki.com

The Pages project `velorki-app` serves the Flutter web build
(`flutter build web --wasm --no-web-resources-cdn` in `app/`, after
`tool/web_assets.sh`; output `app/build/web`) and, through a
Pages Function, the tile mirror under the same origin, so the app fetches
tiles without CORS.

- `pages/wrangler.toml`: the project config.
- `pages/functions/tiles/[[path]].js`: the function on `/tiles/*`; the logic
  is in `pages/tiles_proxy.mjs`.
- `app/web/_headers` ships with the build: cross-origin isolation by
  `Document-Isolation-Policy: isolate-and-credentialless` with COOP
  `same-origin-allow-popups` (COOP `same-origin` would cut the Google and
  Apple sign-in popups off from the page they answer; Chrome stays isolated,
  Firefox and Safari run without isolation), the Content-Security-Policy
  (every host the app loads from, named there, Google Identity Services,
  Drive, CloudKit JS and CloudKit's hosts among them; `app/web_test/headers.test.mjs`
  holds it), `nosniff`, referrer policy and cache rules
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

## /cloudkit/upload

`POST /cloudkit/upload?url=<encoded upload URL>`: CloudKit JS saves a
record's `body` asset by POSTing it to a one-time `cws.icloud-content.com`
URL that allows CORS for a fixed list of origins, ours not among them. The
app's XMLHttpRequest wrapper (`cloudkit_web_js.dart`) sends that POST here instead;
`pages/cloudkit_upload.mjs` checks the URL (https, `cws.icloud-content.com`
or `pNN-contentws.icloud.com`, no port or credentials, path ending
`/singleFileUpload`, a `tk`), reads the body (16 MB at most, else 413),
forwards it with its Content-Type alone and returns Apple's status and JSON
receipt. Nothing is stored or logged; `tk` is a credential for fifteen
minutes. Other methods are a 405, other URLs a 400.

Tests (Node's built-in runner, no dependencies):

    node --test deploy/cloudflare/test/*.test.mjs

`.github/workflows/web-app.yml` deploys it, after approval in the `release`
environment: on a push to `production` that touches `app/` or this
directory, by hand (Actions → web app → Run workflow, the branch's head), and
from a `v*` tag through `release.yml`'s `web` job. Without a workflow, from
`deploy/cloudflare/pages/`, after `app/tool/web_assets.sh` and the build:
`npx wrangler pages deploy`.

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
kept in `build/web_tile_cache`; `/cloudkit/upload` is forwarded the same way. `python3 tool/web_serve.py --https` serves
https://localhost:8443 instead, the origin the CloudKit Development token and
the Google web client allow, so the iCloud and Google sign-ins work locally
(mkcert's certificate when mkcert is installed, else a self-signed one Chrome
warns about once).
