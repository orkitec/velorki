# Contributing to Velorki

Thanks for helping. A few rules keep the project easy to work on.

## Where things live

| Directory | What | Licence |
|-----------|------|---------|
| `app/` | Flutter app (iOS + Android) and its pure-Dart packages | AGPL-3.0-only |
| `web/` | the website and the thin relay (OAuth token exchange, AI relay, share links), Next.js on Node | AGPL-3.0-only |
| `brouter/` | routing profiles and the segment updater | AGPL-3.0-only (profiles carry BRouter's MIT header) |
| `deploy/` | self-hosting: compose file, Caddy, systemd units | AGPL-3.0-only |
| `docs/` | architecture, self-hosting, privacy, store checklist | AGPL-3.0-only |

`docs/ARCHITECTURE.md` explains the design and the rule behind it: as much as
possible runs on the phone; the relay only holds what cannot ship in an
open-source app. `docs/OPEN_ITEMS.md` is what is still open.

## Setup

1. Install the toolchain with [mise](https://mise.jdx.dev): `mise install` in the
   repository root gives you Flutter, Java and Node at the pinned versions.
2. Android SDK: `app/README.md` explains the command-line-tools setup; iOS needs
   Xcode on a Mac.
3. `cd app && flutter pub get && tool/gen.sh` then
   `flutter run --dart-define-from-file=env/dev.json`.
4. `cd api && npm ci && npm run dev` for the relay (optional; the app works
   without it, with the integrations hidden).

## Pull requests

- One topic per PR. Keep the description short and factual.
- CI must be green: `dart format`, `flutter analyze`, tests for `app/` and the
  packages; `npm run lint`, `typecheck`, `test`, `build`, `check:deps` for `web/`.
- The relay must stay deployable as a plain Node process: no native addons, no
  Bun/Deno/edge-only dependencies. `npm run check:deps` enforces it.
- New user-facing strings go into `app/lib/l10n/app_en.arb` only; other
  languages come from Crowdin. After the first Crowdin sync, do not edit the
  other ARB files by hand, and the same holds for `web/messages/*.json` and
  `web/content/*` outside `en`.
  See [docs/LOCALISATION.md](docs/LOCALISATION.md).
- Commit messages: imperative subject, a body that says why. No trailers or
  tool attributions.
- By contributing you agree that your contribution is licensed under
  AGPL-3.0-only, the licence of the whole repository, and you sign the
  Contributor Licence Agreement below.

## Contributor Licence Agreement

The repository is AGPL-3.0-only, but the app also ships through the App Store
and Google Play, whose terms do not sit well with the GPL. That works only
because Orkitec can distribute the app under other terms as well, and that in
turn needs a licence from every contributor. [`CLA.md`](CLA.md) is that
agreement — it covers individuals and companies, and it does not take your
copyright away.

You sign it once, on your first pull request: a bot comments there with the
sentence to post as a reply, you post it, and the check goes green. Later pull
requests need nothing. Without a signature a pull request cannot be merged.

## Reporting bugs

Open an issue with the app version (Settings → About), platform, and steps.
For anything security-related see `SECURITY.md`.
