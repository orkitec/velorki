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
     `https://app.velorki.com` and `http://localhost:8080`; no redirect URIs.
7. **Verification:** when the app is ready, **Publish app** under Audience and
   submit for verification (branding review; `drive.appdata` is not a
   restricted scope, so no security assessment). Until then only test users
   can sign in and Google shows an "unverified app" notice.

Hand over: the iOS client id, the web client id (the Android clients need no
id in the app).

## CloudKit web token

1. icloud.developer.apple.com → CloudKit Database → container
   `iCloud.com.orkitec.velorki`.
2. **API Access → API Tokens → +**, once for **Development** and once for
   **Production** (switch the environment at the top):
   - Name `web planner`.
   - Sign in callback: **postMessage**.
   - Allowed origins: `https://app.velorki.com`, `http://localhost:8080`.
3. Hand over both tokens.

The schema must be deployed to Production before the Production token is
used (done 2026-10-18 for `Route` and `Ride`; redeploy after any schema
change).
