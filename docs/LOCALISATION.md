# Localisation

English is the source language, German is the first target. Translation runs
through [Crowdin](https://crowdin.com); `crowdin.yml` in the repository root
says what is translated.

## How a string travels

| Source, edited by hand | Target, written by Crowdin |
|------------------------|----------------------------|
| `app/lib/l10n/app_en.arb` | `app/lib/l10n/app_<lang>.arb` |
| `web/messages/en.json` | `web/messages/<lang>.json` |
| `web/content/en/**/*.md` | `web/content/<lang>/**/*.md` |

`.github/workflows/crowdin.yml` uploads a source file to Crowdin when it
changes on `main`, and every Monday morning downloads whatever is finished into
the branch `l10n/crowdin` and opens a pull request titled "Update translations".
Nothing reaches `main` without review. The download can also be started by hand
from the Actions tab. A translation pull request can never touch a source file:
Crowdin only ever writes a target language, and English is the source.

The app's `supportedLocales` is generated from the ARB files present, so a
merged `app_de.arb` enables German with no code change. The website lists its
locales from `web/messages/*.json`, but through a generated file — see "Adding
a language".

## Rules

- After the first Crowdin sync, never edit a non-English file by hand: German
  is edited in Crowdin, not in the repository. The next download overwrites a
  hand edit, and the change is invisible in Crowdin.
- New strings go into the English source only. Give an ARB key a `@key`
  description: it is the only context a translator gets.
- Placeholders are ICU, as in the ARB (`{count}`, `{distance}`). They must
  survive translation unchanged, in any order the language needs.
- In Markdown, front matter keys stay as they are; only `title` and
  `description` are translated. `draft: true` stays `true`.
- `app/test/l10n/arb_test.dart` checks that every translated ARB declares its
  own locale and carries no key English does not have. It runs in CI with the
  rest of `flutter test`.

## One-time setup (Steffen)

1. Create the project at crowdin.com: source language English, target language
   German, file structure "preserve hierarchy" (it must match `crowdin.yml`).
2. Request the open-source plan at
   <https://crowdin.com/page/open-source-project-setup-request>. What to say:
   the repository is `github.com/orkitec/velorki`, all of it public and open
   source (Apache-2.0 for the app, AGPL-3.0-only for the relay and website);
   the app itself is free, and the only paid part is the "Velorki Plus"
   subscription for the few features that need our servers or a partner
   account; the strings being translated are the app and the website, both
   public.
3. Create a personal access token (Account settings → API → New token) with
   the scopes the GitHub action needs: **Projects** (list and read),
   **Source files and strings**, **Translations**. Copy it once.
4. Add two repository secrets (Settings → Secrets and variables → Actions):
   - `CROWDIN_PROJECT_ID` — the numeric id from the project's settings
   - `CROWDIN_PERSONAL_TOKEN` — the token from step 3
   Without both, the workflow's `token` job skips everything, and forks never
   reach our project at all.
5. First run: dispatch the workflow once (Actions → crowdin → Run workflow)
   with **upload_translations = true**. The German already in the repository
   goes up and is approved in Crowdin; without it the first download would
   replace it with empty strings. The English sources go up in the same run,
   so nothing else has to be pushed. Do this before any scheduled download.
6. Optional: turn on pre-translation from machine translation in the project
   settings, so a new language starts from a draft instead of an empty file. A
   machine draft still has to be reviewed before the pull request is merged.

## Adding a language

1. Add the target language in Crowdin's project settings.
2. Translate. The next Monday's pull request brings
   `app/lib/l10n/app_<lang>.arb`, `web/messages/<lang>.json` and
   `web/content/<lang>/...`; a language nobody has started yet brings no files
   (`skip_untranslated_files`).
3. For the website, run `npm run locales` in `web/` on that branch and commit
   `src/i18n/locales.generated.ts` — the routing table is imported by client
   code and cannot read the directory itself.
4. The app needs nothing further; `flutter gen-l10n` (`bash app/tool/gen.sh`)
   picks the new ARB up.

## Translators

The Crowdin project is public: anyone can open it, pick a language and start.
New members are approved in Crowdin's members list. Translators need no GitHub
account and never touch this repository — the workflow carries their work
across. Ask in a GitHub issue for a language that is not listed yet.
