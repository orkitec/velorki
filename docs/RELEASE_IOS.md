# iOS release setup

What has to be done once, on the Mac, before `git tag v1.0.0 && git push --tags`
signs and uploads an iOS build. Android is in
[`app/fastlane/README.md`](../app/fastlane/README.md).

Everything after the one-time setup runs read-only: no lane and no workflow can
create or revoke a certificate.

## One-time, on the Mac

1. **Create the private certificates repository.** `orkitec/velorki-certs`,
   private, empty. It holds the distribution certificate and the provisioning
   profiles, encrypted; anyone who can read it *and* knows the passphrase can
   sign as Orkitec.

2. **Install the tools.** From the repository root:

   ```sh
   cd app && bundle install
   ```

   Xcode and its command line tools have to be installed and licensed
   (`sudo xcodebuild -license accept`).

3. **Point match at the repository.** `app/fastlane/Matchfile` is already
   written; `fastlane match init` only regenerates it, so run it only if the
   URL changes:

   ```sh
   cd app && bundle exec fastlane match init      # storage: git, URL as below
   ```

   Otherwise just export the URL and pick a passphrase:

   ```sh
   export MATCH_GIT_URL=https://github.com/orkitec/velorki-certs.git
   export MATCH_PASSWORD='…'                      # keep it in the password manager
   ```

4. **Create the App Store Connect API key.** App Store Connect → *Users and
   Access* → *Integrations* → *App Store Connect API* → **+**, role **App
   Manager**. The `.p8` downloads once and cannot be downloaded again; put it in
   the password manager. Note the **Key ID** and the **Issuer ID** on the same
   page, then:

   ```sh
   export ASC_KEY_ID=…
   export ASC_ISSUER_ID=…
   export ASC_KEY_P8_BASE64="$(base64 -i AuthKey_XXXXXXXX.p8)"
   ```

5. **Create the certificate and the profiles.** This is the only run with write
   access to the Apple account:

   ```sh
   cd app && MATCH_READONLY=false bundle exec fastlane ios certs
   ```

   It creates one distribution certificate and an App Store profile for each of
   the three bundle ids:

   | Bundle id | Xcode target |
   |---|---|
   | `com.orkitec.velorki` | `Runner` |
   | `com.orkitec.velorki.VelorkiLiveActivity` | `VelorkiLiveActivity` |
   | `com.orkitec.velorki.share` | `VelorkiShare` |

   If match asks to register an identifier or a capability, say yes — the App
   Group `group.com.orkitec.velorki` that the share extension writes through
   has to exist on all three. Check afterwards in the Developer Portal that the
   app id and the share extension id both carry App Groups, and that
   `VelorkiLiveActivity` carries Push Notifications (Live Activities).

   Commit nothing: match pushes the encrypted material to `velorki-certs`
   itself.

6. **Create a fine-grained PAT for CI** with *Contents: read* on
   `orkitec/velorki-certs` only, then:

   ```sh
   printf 'x-access-token:%s' "$PAT" | base64
   ```

   That string is `MATCH_GIT_BASIC_AUTHORIZATION`; it lets a runner clone the
   certificates repository over https without an SSH key.

## GitHub secrets

Repository → *Settings* → *Secrets and variables* → *Actions*. Exact names,
because `.github/workflows/ios-release.yml` skips every signing step when one
of them is empty:

| Secret | What it is |
|---|---|
| `MATCH_GIT_URL` | `https://github.com/orkitec/velorki-certs.git` |
| `MATCH_PASSWORD` | the match encryption passphrase |
| `MATCH_GIT_BASIC_AUTHORIZATION` | base64 of `x-access-token:<PAT>`, contents-read on the certs repo |
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | App Store Connect issuer id |
| `ASC_KEY_P8_BASE64` | base64 of the `.p8` private key |
| `APP_ENV_PROD_JSON` | the contents of `app/env/prod.json`; **shared with the Android release**, already set if `release.yml` uploads to Play |

Also create the `release` **environment** (*Settings* → *Environments*) with
Steffen as a required reviewer, if `release.yml` has not created it already.
Both release workflows run in it.

## Running a build by hand

`app/env/prod.json` is not in git — write it from the password manager first
(`app/env/example.json` shows the shape). Then:

```sh
cd app
export MATCH_GIT_URL=… MATCH_PASSWORD=… ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8_BASE64=…
bundle exec fastlane ios beta          # build + TestFlight
bundle exec fastlane ios release       # build + App Store Connect, no submission
```

Both lanes flip the three targets to manual signing, which rewrites
`app/ios/Runner.xcodeproj/project.pbxproj`. Undo it afterwards so Xcode keeps
signing development builds automatically:

```sh
git checkout app/ios/Runner.xcodeproj
```

## What a tag does

1. `git tag v1.2.3 && git push origin v1.2.3`.
2. `release.yml` builds the Android AAB and APK and creates the GitHub Release;
   `ios-release.yml` starts in parallel and **waits for approval** — the
   `release` environment has a required reviewer.
3. Approve it under *Actions* → the run → *Review deployments* → **Approve and
   deploy**. Without approval nothing is signed and nothing is uploaded.
4. The job signs, uploads the build to TestFlight and attaches
   `Velorki.ipa` to the tag's GitHub Release. Processing in App Store Connect
   takes a few more minutes before the build appears to testers.
5. Promoting a TestFlight build to the App Store is not automated: run
   `bundle exec fastlane ios release` from the Mac and submit for review in App
   Store Connect. The App Privacy answers, the age rating and the metadata are
   listed in [`STORE_CHECKLIST.md`](STORE_CHECKLIST.md).

Without the secrets — a fork, or before step 5 above — the workflow builds an
unsigned archive, prints a notice and finishes green.
