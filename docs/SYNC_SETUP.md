# Cloud sync setup

One-time console setup for syncing with Google Drive and for signing the web
planner into iCloud or Google. Nothing here is a secret: client ids and the
CloudKit web token are public and bound to our app ids and origins.

## Google Cloud

1. console.cloud.google.com → project picker → **New project** `Velorki`.
2. **APIs & Services → Library → Google Drive API → Enable.**
3. **Google Auth Platform → Branding** (the consent screen):
   - App name `Velorki`, support email, logo (the app icon, 120×120 PNG).
   - App home page `https://velorki.com`, privacy policy
     `https://velorki.com/privacy`, terms `https://velorki.com/terms`.
   - Authorized domains: `velorki.com`.
4. **Audience:** user type **External**. While it is in *Testing*, add the
   Google accounts that may sign in under **Test users**.
5. **Data access → Add or remove scopes:** only
   `https://www.googleapis.com/auth/drive.appdata` (the app's hidden folder;
   nothing else in the rider's Drive).
6. **Clients → Create client**, three times:
   - **Android:** package `com.orkitec.velorki`, SHA-1 of the **upload key**.
     Create a second Android client with the SHA-1 of **Play's app signing
     key** (Play Console → Test and release → App integrity → App signing).
   - **iOS:** bundle id `com.orkitec.velorki`. Note the iOS client id and its
     reversed form (`com.googleusercontent.apps.…`), the app's URL scheme.
   - **Web application:** authorized JavaScript origins
     `https://app.velorki.com`, `https://localhost:8443` and
     `http://localhost:8080`; no redirect URIs.
7. **Verification:** when the app is ready, **Publish app** under Audience and
   submit for verification (branding review; `drive.appdata` is not a
   restricted scope, so no security assessment). Until then only test users
   can sign in and Google shows an "unverified app" notice.

In the app: the iOS client id is `GIDClientID` in `ios/Runner/Info.plist`,
its reversed form a URL scheme there. The Android clients need no id in the
app, but Android's sign-in (Credential Manager) needs the web client id as
its server client id: `VELORKI_GOOGLE_WEB_CLIENT_ID` in `env/web.json`,
`env/prod.json` (the `APP_ENV_PROD_JSON` secret), `env/phone.json` and
`env/local.json`. Empty, Android offers no Google sync. No client secret
goes anywhere.

## CloudKit web token

1. icloud.developer.apple.com → CloudKit Database → container
   `iCloud.com.orkitec.velorki`.
2. **API Access → API Tokens → +**, once for **Development** and once for
   **Production** (switch the environment at the top):
   - Name `web planner`.
   - Sign in callback: **postMessage**.
   - Allowed origins: `https://app.velorki.com`, and in the Development
     token also `https://localhost:8443` (the console takes https only; the
     local server serves https there).
3. Both go into `app/env/web.json` (`VELORKI_CLOUDKIT_TOKEN_DEVELOPMENT`,
   `VELORKI_CLOUDKIT_TOKEN_PRODUCTION`); they are public, bound to the origins.
   The planner picks Development on localhost (`tool/web_serve.py --https`)
   and Production everywhere else.

The schema must be deployed to Production before the Production token is
used (done 2026-10-18 for `Route` and `Ride`; redeploy after any schema
change).

## Plus on the web

Each app writes one `PlusDevice` record into the `Library` zone
(`plus_<device id>`: `appUserId` String, `platform` String, `lastSeen` and
`modifiedAt` Int(64), `schemaVersion` Int(64)); a Development build creates
the type on its first save. The relay queries it with a filter on
`lastSeen`, so before Plus works in a browser:

1. CloudKit Database → Development → Schema → Indexes → `PlusDevice`: add
   `lastSeen` **Queryable** (and `recordName` Queryable, which the console
   asks for on any type that is queried).
2. **Deploy Schema Changes…** to Production.
3. The relay's environment: `CLOUDKIT_API_TOKEN` (the Production web token
   above), `CLOUDKIT_ENVIRONMENT=production`, and `PLUS_TOKEN_SECRET` (32
   random bytes, base64). `CORS_ORIGINS` names every planner origin
   (`https://app.velorki.com`, and for local work `https://localhost:8443`
   and `http://localhost:8080` on a non-production relay).

Google needs nothing more: the Drive store writes a file per record with the
fields in `appProperties`.
