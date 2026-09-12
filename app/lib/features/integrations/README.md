# Integrations: Strava and Ride with GPS

Everything in this folder talks to a partner service **directly from the
phone**. The relay (`api/`) is involved exactly twice: it exchanges an OAuth
code for a token and it refreshes a Strava token, because both need a client
secret that an open-source app cannot hold. No ride data ever passes through
our servers.

```
features/integrations/
├── common/            OAuth, tokens, rate bucket, the shared route model
├── strava/            Strava client, authorise URLs, connector
├── rwgps/             Ride with GPS client, authorise URL, connector
├── application/       upload, send, import and the connect controller
└── presentation/      settings tiles, route lists, the two menus
```

Both connections are **Velorki Plus** features (`PlusFeature.stravaConnection`,
`PlusFeature.rwgpsConnection`). Until the paywall lands in M6 an unentitled
rider sees a placeholder card and disabled buttons.

An empty `VELORKI_API_URL`, or an empty `VELORKI_STRAVA_CLIENT_ID` /
`VELORKI_RWGPS_CLIENT_ID`, hides the service entirely — that is the pure-local
fork build.

## Where the authorisation comes back from, and why there are two ways

`OAuthFlow` listens on **both** paths at once, because neither covers
everything:

* **The web session.** `flutter_web_auth_2` opens the authorisation page and is
  itself told about the redirect — a Chrome Custom Tab on Android, an
  `ASWebAuthenticationSession` on iOS. This is the normal path, and the only one
  for Ride with GPS.
* **The deep link.** Strava's iOS app-to-app flow is launched with
  `url_launcher`, so there is no session to report anything: the Strava app
  sends the rider back with an ordinary `velorki://oauth/strava?code=…` link,
  which arrives through `app_links` on `IncomingFileService.deepLinks` and is
  republished by `oauthDeepLinksProvider`. The same path catches the case where
  the system hands the redirect to the app instead of to the session.

Both are subscribed *before* anything is opened, and whichever answers first
wins (`Future.any`). A deep-link stream that simply ends never decides the race.

**Platform split for Strava.** Strava documents `strava://oauth/mobile/authorize`
for iOS and the https URL for Android, where the installed Strava app registers
an intent filter for `https://www.strava.com/oauth/mobile/authorize` and takes
it over by itself. `StravaConnector.preferAppToApp` is therefore `true` on iOS
only, and `url_launcher.canLaunchUrl` decides whether the app is there at all.

### Platform registration

* **Android** (`android/app/src/main/AndroidManifest.xml`): the plugin's
  `com.linusu.flutter_web_auth_2.CallbackActivity` is registered for
  `velorki://oauth/*`, with `android:exported="true"` and
  `android:taskAffinity=""` as its README requires. `MainActivity`'s own
  `velorki` filter was narrowed to `android:host="s"` (the M6 share links), so
  the two activities never match the same URI — otherwise Android would ask the
  rider which one should open the callback.
* **iOS** (`ios/Runner/Info.plist`): `CFBundleURLSchemes` already carries
  `velorki`, which is all `ASWebAuthenticationSession` and `app_links` need.
  **TODO (M7):** add `LSApplicationQueriesSchemes` with `strava` so
  `canLaunchUrl(strava://…)` can answer `true` on iOS; without it the app-to-app
  flow silently degrades to the web flow, which still works.

## Strava

Documentation: <https://developers.strava.com/docs/reference/>,
<https://developers.strava.com/docs/uploads/>,
<https://developers.strava.com/docs/authentication/> (read 2026-09-12).

**Authentication header:** `Authorization: Bearer <access_token>`, put on by
`OAuthTokenInterceptor`.

| Purpose | Call |
|---|---|
| Authorise (web) | `GET https://www.strava.com/oauth/mobile/authorize?client_id=…&redirect_uri=velorki://oauth/strava&response_type=code&approval_prompt=auto&scope=read,activity:write,activity:read` |
| Authorise (app) | `strava://oauth/mobile/authorize?…` — same query |
| Token exchange | relay `POST /oauth/strava/token` `{code, redirect_uri}` |
| Token refresh | relay `POST /oauth/strava/refresh` `{refresh_token}` |
| Upload a ride | `POST https://www.strava.com/api/v3/uploads`, `multipart/form-data`: `file`, `data_type` (`gpx`\|`fit`), `name`, `description`, `sport_type` (`Ride`), `external_id` |
| Poll an upload | `GET /api/v3/uploads/{uploadId}` → `{id, id_str, external_id, error, status, activity_id}` |
| List routes | `GET /api/v3/athletes/{id}/routes?page=&per_page=` |
| Export a route | `GET /api/v3/routes/{id}/export_gpx` |
| Disconnect | `POST https://www.strava.com/oauth/deauthorize?access_token=…` |

Notes:

* **Polling backoff** is 2, 4, 8 then 16 s (`StravaClient.uploadPollBackoff`),
  stopping as soon as `activity_id` is set or `error` is non-null. An upload
  that is still pending after the last attempt is reported as "Strava is still
  processing"; it is not retried, because Strava will finish on its own and a
  second upload would create a duplicate activity.
* **Never upload twice.** A successful upload is written into the ride's
  `uploads` JSON as `{"strava": {"upload_id", "activity_id", "status",
  "uploaded_at", "url"}}`; the menu then offers "View on Strava"
  (`https://www.strava.com/activities/{id}`) instead of another upload.
* **Reads are budgeted** by a client-side sliding-window bucket of 90 per 15
  minutes (`TokenBucket.stravaReads`); Strava's own limit is 100, and the
  remaining ten are left as headroom. Uploads are writes and are not counted.
* **Seven-day cache.** The fetched route list is stored in
  `shared_preferences` and dropped after seven days, on read and at launch
  (`ExternalRouteListCache`). An imported route keeps its
  `external_fetched_at` and `external_ids` in the `routes` row.
* **`POST /oauth/revoke`** (the successor to `deauthorize`) needs HTTP basic
  auth with the client secret and therefore cannot be called from the app; the
  legacy `deauthorize` endpoint authenticates with the access token itself.
* **Routes cannot be created** through Strava's API. "Send to Strava" in the
  route detail explains that and offers the GPX export instead.
* **Base URL** moves to `https://api-v3.strava.com` on 2027-01-04; that is the
  single constant `StravaClient.apiBase`.
* AI descriptions must be disabled for `source == strava`; M4 only sets the
  source correctly, the rule itself lands with the assistant in M6.

## Ride with GPS

Documentation: <https://ridewithgps.com/api/v1/doc/authentication> and the
machine-readable spec at <https://ridewithgps.com/api/v1/openapi.yaml>
(read 2026-09-12).

**Authentication header:** `Authorization: Bearer <access_token>` — and nothing
else. `x-rwgps-api-key` and `x-rwgps-auth-token` belong to the *basic*
authentication scheme (for single-user and organisation accounts, where they
are paired with an auth token from `POST /api/v1/auth_tokens.json`); the
documentation's OAuth section uses the bearer header alone, and the app
therefore does **not** send the API key. There is no API version header.

| Purpose | Call |
|---|---|
| Authorise | `GET https://ridewithgps.com/oauth/authorize?client_id=…&redirect_uri=velorki://oauth/rwgps&response_type=code` |
| Token exchange | relay `POST /oauth/rwgps/token` `{code, redirect_uri}` |
| Token refresh | none — tokens do not expire; the relay answers `501` |
| Who am I | `GET https://ridewithgps.com/api/v1/users/current.json` |
| Upload a route | `POST /api/v1/routes.json`, `multipart/form-data`: `file`, `name`, `description` → `202 {"task": {...}}` |
| Upload a trip | `POST /api/v1/trips.json`, same fields (+ `gear_id`) |
| Poll a task | `GET /api/v1/tasks/{id}.json` until `status == "completed"`, then read `items[]` and `errors[]` |
| List routes | `GET /api/v1/routes.json?page=&page_size=` → `{routes: [...], meta: {pagination}}` |
| List trips | `GET /api/v1/trips.json?page=&page_size=` |
| Export a route | `GET /api/v1/routes/{id}.gpx` (GPX 1.1 track, full resolution, no waypoints) |

Notes:

* **Task outcome.** `items[]` entries are `{item_type: route|trip, item_id,
  item_url}`; `errors[]` entries are `{code, message, item_type?, item_id?}`
  with `code` one of `duplicate`, `time_data_missing`, `no_tracks`,
  `empty_file`, `parse_failed`, `failed_to_process`, `weigh_in_failed`,
  `error`.
* **Trips need timestamps.** An untimed track is refused by the app before the
  upload, with a message pointing at the route upload instead; Ride with GPS
  would otherwise answer `time_data_missing`.
* **Visibility** always follows the account's default privacy setting and
  cannot be set through these endpoints.
* **Revoking** needs `POST /oauth/revoke.json` with the client secret, so the
  app cannot do it; Disconnect deletes the token from the phone and the rider
  can remove the authorisation on ridewithgps.com.
* Page size is between 20 and 200; the app asks for 50.

## What needs a real account to verify

Everything below is exercised against fakes in `test/features/integrations/`
but has never touched the real services:

1. the redirect allowlist on the deployed relay and the Strava "Authorization
   Callback Domain";
2. the app-to-app flow on a device with the Strava app installed;
3. Strava's actual upload timing against the 2/4/8/16 s backoff;
4. whether Strava accepts `sport_type` alongside the deprecated
   `activity_type` on `POST /uploads`;
5. the exact shape of `errors[]` a real Ride with GPS task returns.
