# Contributing to Velorki

Thanks for helping. A few rules keep the project easy to work on.

## Where things live

| Directory | What | Licence |
|-----------|------|---------|
| `app/` | Flutter app (iOS + Android) and its pure-Dart packages | Apache-2.0 |
| `api/` | the thin relay (OAuth token exchange, AI relay, share links), TypeScript on Node | AGPL-3.0-only |
| `brouter/` | routing profiles and the segment updater | Apache-2.0 (profiles carry BRouter's MIT header) |
| `deploy/` | self-hosting: compose file, Caddy, systemd units | Apache-2.0 |
| `docs/` | architecture, self-hosting, privacy, store checklist | Apache-2.0 |

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
  packages; `npm run lint`, `typecheck`, `test`, `check:deps` for `api/`.
- The relay must stay deployable as a plain Node process: no native addons, no
  Bun/Deno/edge-only dependencies. `npm run check:deps` enforces it.
- New user-facing strings go into `app/lib/l10n/app_en.arb` only; other
  languages are handled by the GL Strings integration. Do not edit the other
  ARB files by hand.
- Commit messages: imperative subject, a body that says why. No trailers or
  tool attributions.
- By contributing you agree that your contribution is licensed under the licence
  of the directory it lands in.

## Reporting bugs

Open an issue with the app version (Settings → About), platform, and steps.
For anything security-related see `SECURITY.md`.
