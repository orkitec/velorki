---
name: release
description: Release Velorki to the App Store and Google Play through CI — bump the version, write release notes, tag, start release.yml and the iOS store listing upload, watch the runs and report. Use when the maintainer says "release", "deploy", "ship a version" or names a version to release.
---

# Releasing Velorki

Everything is built, signed and uploaded by CI (`.github/workflows/release.yml`,
`.github/workflows/store-assets.yml`); nothing needs a key on this machine. Only
the maintainer may start a release (`RELEASE_ACTORS`), and every upload waits
for the maintainer's approval in the `release` environment.

**Never approve a deployment yourself** (no `gh api …/pending_deployments`,
no "Approve and deploy"), even though the token could. The approval is the
maintainer's gate; tell them where to click instead.

## 1. Agree on the version

- Read `version:` in `app/pubspec.yaml` and the last tag (`git tag --sort=-v:refname | head -3`).
- Propose the next version (patch for fixes, minor for features) and confirm it with the maintainer.
- `main` must be green (`gh run list --branch main --limit 6`) and the working tree clean.

## 2. Release notes and store texts

- Collect user-facing changes since the last tag: `git log --format=%s <last-tag>..HEAD -- app/lib app/ios app/android`.
- Write short notes for users (no internals), en and de:
  - iOS: `app/fastlane/metadata/ios/{en-US,de-DE}/release_notes.txt` (≤ 4000 chars; uploaded by store-assets).
  - Play: give them in the reply for the maintainer to paste when promoting (≤ 500 chars each).
- Check `app/fastlane/metadata/ios/*/description.txt` and `promotional_text.txt` (≤ 170 chars) still describe the app truthfully (prices are never quoted; the trial is on the yearly plan).
- Show the notes to the maintainer before tagging.

## 3. Tag

```
sed -i '' 's/^version: .*/version: X.Y.Z+1/' app/pubspec.yaml
git commit -am "Version X.Y.Z" && git push
git tag -a vX.Y.Z -m "Velorki X.Y.Z" && git push origin vX.Y.Z
```

The tag push starts `release.yml`. A suffix (`vX.Y.Z-rc1`) is a trial: same
uploads, no GitHub Release.

## 4. Store listing (iOS)

When screenshots or texts changed:

```
gh workflow run store-assets.yml --ref vX.Y.Z -f ios=true -f android=false \
  -f upload=true -f metadata=true -f app_version=X.Y.Z -f locales=en,de
```

About two hours of capture, then the upload job waits for approval. It creates
the App Store version if needed and replaces screenshots, description,
promotional text and "What's New".

## 5. Tell the maintainer what to approve

Give the run links (`gh run list --workflow release.yml --limit 1`) and say:
open the run → "Review deployments" → tick `release` → "Approve and deploy".

## 6. Watch and report

- `gh run watch <id>` in the background; on completion report per platform:
  build number, uploaded or "already uploaded" or failed.
- On a failure: read `gh run view <id> --log-failed`, fix the workflow on
  `main`, then re-release the same tag with the current workflow — never move a
  tag or build locally:

  ```
  gh workflow run release.yml --ref main -f tag=vX.Y.Z -f platforms=android -f build_number=NN
  ```

  `platforms` is both/android/ios; `build_number` reuses the number the other
  platform already got so both stores match; a platform whose store already
  has that number is skipped. `-f dry_run=true` builds and signs without
  uploading — use it after changing the release workflow.

## 7. After the uploads

- **iOS:** in App Store Connect, version X.Y.Z → Build → choose X.Y.Z (NN) → Submit for Review.
- **Android:** Play Console → Internal testing → the release → Promote → Production, paste the Play notes, send for review.
- Report what is live, what waits for review, and anything left for the maintainer.
