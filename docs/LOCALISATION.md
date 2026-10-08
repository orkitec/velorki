# Localisation

English is the source language; German, French, Spanish, Italian and Dutch are the translations. Translations are
written in the repository, in the commit that changes the English, by the
coding agent; [Crowdin](https://crowdin.com) holds them so that people can
improve them. `crowdin.yml` in the repository root says what is translated.

## How a string travels

| Source | Target, written with it, refined in Crowdin |
|------------------------|----------------------------|
| `app/lib/l10n/app_en.arb` | `app/lib/l10n/app_<lang>.arb` |
| `web/messages/en.json` | `web/messages/<lang>.json` |
| `web/content/en/**/*.md` | `web/content/<lang>/**/*.md` |
| `app/fastlane/metadata/ios/en-US/*.txt` | `app/fastlane/metadata/ios/<store locale>/*.txt` |
| `app/fastlane/metadata/android/en-US/*.txt` | `app/fastlane/metadata/android/<store locale>/*.txt` |
| `app/store/slides_en.json` | `app/store/slides_<lang>.json` |

`.github/workflows/crowdin.yml` uploads the sources and the translations to
Crowdin when they change on `main`, the translations as approved, and every
Monday morning downloads what people changed there into the branch
`l10n/crowdin` and opens a pull request titled "Update translations" (the
translated ARB files without the `@key` metadata Crowdin copies into them).
While that pull request is open, a push uploads only the sources: the
repository's older copy would overwrite the newer text. Merge it first. The
download can also be started by hand from the Actions tab. A translation pull
request can never touch a source file: Crowdin only ever writes a target
language, and English is the source.

The app's `supportedLocales` is generated from the ARB files present, so a
merged `app_de.arb` enables German with no code change. The website lists its
locales from `web/messages/*.json`, but through a generated file — see "Adding
a language".

## Rules

- A change to an English source carries its translation into every other
  language in the same commit, matching the terms that language already uses.
  Give an ARB key a `@key` description: it is the context a translator in
  Crowdin gets.
- Legal pages (imprint, privacy, terms) and the store texts get a person's
  read in each language before they go live.
- Placeholders are ICU, as in the ARB (`{count}`, `{distance}`). They must
  survive translation unchanged, in any order the language needs.
- In Markdown, front matter keys stay as they are; only `title` and
  `description` are translated. `draft: true` stays `true`: it marks a text
  that has not been reviewed, and the site renders it with a banner and
  `robots: noindex`, and leaves it out of the sitemap, `llms.txt` and
  `llms-full.txt`. A legal text whose body still contains `{{` shows a short
  notice instead of the template.
- Turn-by-turn labels (`navTurnLeft`, `navTurnRight`, `navTurnSlightLeft`,
  `navTurnSlightRight`, `navTurnSharpLeft`, `navTurnSharpRight`, `navKeepLeft`,
  `navKeepRight`, `navUTurn`, `navRoundaboutExit`, `navExitLeft`,
  `navExitRight`, `navArrive`, `navContinue`, `navBackToRoute`) are also spoken
  inside a longer sentence ("In 200 metres, turn left"), where the app
  lower-cases the first letter. They must be written so that survives: never
  start one with a word that is capitalised wherever it stands, such as a
  German noun. "Am Ziel ankommen", not "Ziel erreichen".
- Nothing English may reach a translated screen. The checks, all generic
  over the languages present, fail CI otherwise:
  - `app/test/l10n/arb_test.dart`: every translated ARB declares its locale,
    has every English key and no other, keeps each message's ICU arguments,
    and translates every message with words in it, unless `sameAsEnglish`
    in the test names it with a reason (brands, units, borrowed words).
  - `app/test/l10n/hardcoded_strings_test.dart`: no literal with letters in
    a `Text`, `TextSpan`, tooltip, label, title, snack bar, notification or
    share text under `app/lib`, and no exception's `message` or `toString()`
    on a screen; failures are shown with `errorText(l10n, error)`
    (`features/shared/presentation/error_text.dart`), and code without a
    `BuildContext` describes them with a `LocalizedText`
    (`core/l10n/localized_text.dart`). Exceptions go in its `_allowed` list,
    with the reason.
  - `npm run locales -- --check` in `web/` (CI: `web.yml`): each catalogue
    has English's keys, ICU arguments and rich-text tags, no message with
    words is identical to English unless `SAME_AS_ENGLISH` names it, and
    every `content/en` page has a file in each locale (a `draft: true` one
    counts; only the bilingual imprint is exempt and falls back to English).
- Text outside Flutter's strings is native: iOS permission prompts live in
  `app/ios/Runner/<lang>.lproj/InfoPlist.strings` (English stays in
  `Info.plist` as the fallback; the watch app has its own `.xcstrings`
  catalogues), and Android has no native text beyond the brand name, only
  `res/xml/locales_config.xml` for the per-app language picker.
  `app/test/l10n/native_strings_test.dart` holds all of it to the ARB
  languages, and `app/test/l10n/store_texts_test.dart` checks the store
  texts and slide captions of every translated locale against English.
- A language must pass the widget suite in its own locale:
  `flutter test --dart-define=VELORKI_TEST_LOCALE=<lang>` from `app/` (or
  `VELORKI_TEST_LOCALE=<lang> flutter test`) pumps every harness-built screen
  in that language. `app.yml` runs it for German on every push and
  `locales.yml` for every language by hand, so a translation that no longer
  fits its layout is a failed build, not a bug report.

## Store listing texts

The App Store and Play Store listing texts are fastlane metadata, not app
strings: `app/fastlane/metadata/ios/en-US/` (`name.txt`, `subtitle.txt`,
`keywords.txt`, `description.txt`, `promotional_text.txt`) and
`app/fastlane/metadata/android/en-US/` (`title.txt`, `short_description.txt`,
`full_description.txt`), plus the store screenshots' slide captions,
`app/store/slides_en.json`. English is the source in each; Crowdin writes
every other language into its own file or folder, named the way the store
expects rather than `<lang>`.

Both stores mostly use `ll-CC` locale folders (`de-DE`, `fr-FR`, `es-ES`,
`nl-NL`, `pt-BR`...), which is what Crowdin already gives through `%locale%`.
Apple is the exception for a few languages: Italian is `it`, Japanese is
`ja`, Chinese Simplified is `zh-Hans` — `crowdin.yml` maps those under the
iOS file's `languages_mapping`. Play needs no such mapping. The App Store
review note, `app/fastlane/metadata/ios/review_information/notes.txt`, is
not a listing text and is never translated: it lives outside the source glob.

A length check enforces each store's limits (Apple: name 30, subtitle 30,
keywords 100, promotional text 170, description 4000; Play: title 30, short
description 80, full description 4000 — all in Unicode code points, and a
required file may not be empty):

```
python3 app/tool/store_text_check.py
```

It runs in CI as part of `app.yml`'s `check` job. `app/tool/store_text_check_test.py`
is its unit test (`python3 -m unittest app/tool/store_text_check_test.py`).

## One-time setup (Steffen)

1. Create the project at crowdin.com: source language English, target language
   German. The file layout comes from `preserve_hierarchy: true` in
   `crowdin.yml`; the web interface has no setting for it.
2. Request the open-source plan at
   <https://crowdin.com/page/open-source-project-setup-request>. What to say:
   the repository is `github.com/orkitec/velorki`, all of it public and open
   source (AGPL-3.0-only, all of it);
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
2. Translate every source into it in the repository (`app_<lang>.arb`,
   `web/messages/<lang>.json`, `web/content/<lang>/...`, the store texts) and
   push; the upload makes them the approved translations in Crowdin.
3. For the website, run `npm run locales` in `web/` on that branch and commit
   `src/i18n/locales.generated.ts` — the routing table is imported by client
   code and cannot read the directory itself.
4. Native iOS/Android: add `app/ios/Runner/<lang>.lproj/InfoPlist.strings`
   (same keys as `en.lproj`) and its file reference in the pbxproj's
   `InfoPlist.strings` variant group, the language in `Info.plist`'s
   `CFBundleLocalizations` and the pbxproj's `knownRegions`, a `<locale>` in
   `res/xml/locales_config.xml`, and a `de`-style entry in the watch
   `.xcstrings`. A `res/values-<lang>/strings.xml` too if `values/strings.xml`
   ever exists. `native_strings_test.dart` fails until all are there.
5. The Flutter strings need nothing further; `flutter gen-l10n` (`bash app/tool/gen.sh`)
   picks the new ARB up.

## Translators

The Crowdin project is public: anyone can open it, pick a language and start.
New members are approved in Crowdin's members list. Translators need no GitHub
account and never touch this repository — the workflow carries their work
across. Ask in a GitHub issue for a language that is not listed yet.
