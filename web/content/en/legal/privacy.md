---
title: Privacy policy
description: "What Velorki does with your data: no account, routes and rides stay on your phone or in your browser unless you sync them to your own iCloud or Google Drive, and a list of exactly what leaves the device and when."
draft: false
---

Effective date: 23 October 2026.

Velorki is a bike route planning and ride recording app made by Orkitec, for
iPhone, iPad and Android, and a web planner at app.velorki.com. This page
explains what happens to your data.

**Who is responsible.** The controller for everything described here is Steffen
Roemer, trading as "Orkitec", Straße der Pariser Kommune 27, 10243 Berlin,
Germany, ride@velorki.com. No data protection officer is appointed: the
processing described below does not require one under Article 37 GDPR. The full
provider details are on the [imprint](./imprint) page.

## The short version

- There is **no account**. You do not sign up, and we do not know who you are.
- Your routes, your rides and your settings stay **on your phone**, or in your
  browser for the web planner. If you turn on sync, they go to your own iCloud
  or your own Google Drive, never to us.
- Some things need a server: map tiles, routing outside the areas you have
  downloaded, search when you ask for it, and, if you use them, the AI
  assistant, the Strava and RideWithGPS connections (free), and share links. Each is
  described below.
- This **website** has no analytics, no advertising and no tracking, so the
  short notice at the bottom of it asks nothing of you.
- The **web planner** at app.velorki.com works the same way: no account, no
  analytics, your library kept in your browser.
- We do not sell your data, and we do not use it for advertising or profiling.

## What stays on your device

Planned routes, recorded rides, their GPS tracks, your settings, downloaded
offline map regions, downloaded routing tiles and the place-search indexes that
come with them are stored in the app's own storage on your phone. They are not
uploaded anywhere unless you ask for it; the one exception is cloud sync,
described below, which goes to your own iCloud or Google Drive and not to us.
What the web planner keeps in your browser is described under The web planner.

Heart rate, cadence and power from an Apple Watch, a Bluetooth sensor or your
health app are stored with the ride, on the phone, like the track itself. With
the Health switch on in Settings, the app reads heart rate from Apple Health or
Health Connect and writes your finished rides there as cycling workouts; that
exchange happens on your phone and none of it reaches us. Sensor values travel
with a ride only where the ride does: in a GPX, FIT or TCX file you export, in an
upload to Strava or RideWithGPS that you start, or to your own cloud while sync
is on.

If you connect Strava or RideWithGPS, the access tokens for those accounts are
stored in the phone's secure storage (Keychain on iOS, Keystore on Android), in
an encrypted form that only our relay can open, and what you take from Strava
is kept on the phone; see the Strava and RideWithGPS section below.

On Android, the app is excluded from Google's cloud backup and from
device-to-device transfer, so your rides and your access tokens are not copied
off the phone by the system either. To move to a new phone, turn on sync with
Google (described below) or export what you want to keep as GPX, FIT or TCX
files.

## What leaves your device, and when

### Routing

Routing normally happens entirely on your phone, from routing tiles you have
downloaded, and nothing is sent anywhere. For an area you have no tiles for,
the app sends the coordinates of your waypoints to a routing server (BRouter,
run by us) which sends back the route. It needs the waypoints to compute the
route; it does not receive your identity, your other routes or your rides.

Routing tiles and the search indexes beside them are downloaded from our tile
mirror on GitHub (`raw.githubusercontent.com` and `github.com` release
downloads). GitHub learns which 5° tiles you download and your IP address, as
any web request does. The web planner fetches them through app.velorki.com
instead, so GitHub sees Cloudflare and not you.

### Search

Places are searched on your phone, in the search indexes that come with the
routing tiles you downloaded. Nothing you type there leaves the device.

If you tap "Search online for …" at the bottom of the results (or if you have
downloaded no routing tiles, in which case the search box goes online straight
away), what you typed is sent to Photon, a geocoding service, together with a
rough position so that nearby results rank first. Photon returns place
suggestions.

Tapping "Details" on a place's card fetches its details (opening hours,
website and the like) from OpenStreetMap.

### Map tiles

The map is drawn from tiles fetched from OpenFreeMap, and from CyclOSM if you
turn the cycling overlay on. Fetching a tile tells the tile provider which part
of the map you are looking at, and involves your IP address, as any web request
does. Map data is © OpenStreetMap contributors.

### Weather

**The weather map and the route's free forecast.** When you switch on the rain,
the clouds or the wind on the map, or colour a route by the wind or the rain
without Velorki Plus, the app fetches pictures and forecast data directly from
public weather services: the Deutscher Wetterdienst (Germany), the US National
Oceanic and Atmospheric Administration and Iowa State University (USA), NASA,
EUMETSAT, the KNMI (Netherlands) and the Finnish Meteorological Institute. Each
request names a part of the map, or a box around your route, and a time, and
involves your IP address, as any web request does. Your route itself, your rides
and your identity are not sent.

**Finer weather along the route (Velorki Plus).** The app sends our relay the
points along the route rounded to a grid of about 2.5 km, each with its altitude
rounded to 50 m, and the hours you ride there — not the route, its name or your
rides. The relay checks that your subscription is active and asks the US
National Weather Service, Bright Sky (for the Deutscher Wetterdienst's
forecasts) and MET Norway for those grid points. They see our server, not your
phone. Each answer is kept for up to two hours per grid point and shared by
everyone who asks for the same point.

**Rain radar across Europe (Velorki Plus).** The app asks our relay for the part
of the map you are looking at and a time. The relay fetches the radar once for
everyone from EUMETNET OPERA's open archive and, for Italy, from the
Dipartimento della Protezione Civile, keeps it for up to two and a half hours,
and sends back a picture of that part of the map. The radar's providers see our
server, not your phone, and the relay keeps no record of which part of the map
you asked for.

### Strava and RideWithGPS

Both connections are free. Nothing is sent to Strava or RideWithGPS unless you
connect the account yourself and then trigger an action: uploading a ride,
importing a route.

When you connect, the app hands a one-time code to our relay server
(api.velorki.com), which exchanges it for an access token by adding our
application secret, encrypts the token with a key only the relay holds, and
gives it back to the app in that form. Your phone stores the encrypted token in
its secure storage (Keychain on iOS, Keystore on Android), excluded from
backups; it cannot use it on its own, and we do not store it at all.

After that, every upload, route transfer, import and disconnect you trigger
passes through the relay: it decrypts the token for that one request, forwards
the request to Strava or RideWithGPS and passes the answer back to the app. It
keeps neither the file nor the token, nothing of the answer, and no record of
the call. No subscription is checked for these calls; to stop abuse the relay
only keeps short-lived rate-limit counters keyed by the anonymous id of your
installation and by IP address (see Server logs below). Its logs never contain
the token, the request body or that id.

#### Strava

**What Velorki asks for.** Two permissions: `read`, your public Strava profile
(your athlete id and name), and `activity:write`, to upload the rides you
choose to upload. Velorki does not read your activities.

**What it reads and keeps, all of it only on your phone:**

- your athlete id and name, shown in Settings → Connections, until you
  disconnect;
- your list of Strava routes (name, distance, elevation gain, description and
  date), fetched when you open the import screen and kept on the phone for at
  most **48 hours**;
- a route's GPX file, when you import that route; it is stored as a route in
  the app's library, and so is any route you edit from it, only while the
  route still exists on Strava: while the app is open, online and connected,
  it checks the route against Strava again every 48 hours, and removes it if it
  was deleted on Strava or could not be checked for 7 days, and tells you so.
  It is also removed when you delete it or disconnect;
- after an upload, the id of the Strava activity and its link, kept with the
  ride so the app can show "View on Strava", until you disconnect.

A ride you upload is sent to Strava, which processes it as described in
[Strava's privacy policy](https://www.strava.com/legal/privacy). Strava and
Orkitec are each responsible for their own processing.

**Strava data stays with you.** Strava data is only shown to you, in the app.
It is never sent to the AI assistant, never put in a share link and never sent
to RideWithGPS or any other service. We hold no Strava data on our servers.

**Deletion.** Disconnecting Strava in Settings → Connections revokes Velorki's
authorization at Strava, deletes the tokens and deletes every item that came
from Strava from the phone: imported Strava routes and routes edited from them,
the cached route list and the stored activity links. The app then confirms:
"Your Strava data has been deleted from this phone." If you revoke Velorki's
access on strava.com instead, the app notices at its next Strava call, deletes
the same data and tells you. Uninstalling the app deletes it too. Since all of
it is on your phone, these are the ways to delete it; for questions or a
deletion request, write to ride@velorki.com.

**Usage data at Strava.** Strava may monitor and collect data about how
Velorki uses the Strava API (usage data) and may use it for any business
purpose, internal or external, including providing enhancements to the Strava
API or the Strava platform, providing developer or user support, and ensuring
compliance with its API agreement.

#### RideWithGPS

What RideWithGPS does with the data you send it is governed by its own privacy
policy.

### The AI assistant (Velorki Plus)

The assistant is off until you enable it, and the first time you open it you
are asked for consent. You can choose to send only your text, or your text
together with a coarse starting position, or to decline. You can revoke consent
in the settings at any time.

When you use it, the following is sent through our relay server to our AI
provider:

- the text you typed,
- optionally, a starting position **rounded to roughly one kilometre**,
- the language and unit settings, so the answer fits,
- if you ask for a route description, a digest of the route built on your
  phone: distance, ascent, surface shares, the stretches it runs over with
  their road, surface and gradient, its climbs, the towns it passes and the
  places to stop near it, each with its distance along the route and its
  position (to about 10 m). The AI provider receives them as well; a route
  that starts at your home therefore shows where your home is.

No identifier of you or your phone is put into the prompt. The model returns a
structured request: a distance, a shape, place names, preferences. The actual
routing then happens in the app; the model never sees your route.

Our relay passes the request to **OpenRouter, Inc.** (USA), a service that
gives access to language models from several providers, and OpenRouter forwards
it to the provider serving the model we use. We have configured OpenRouter to
send requests only to providers that do not train models on them and do not
retain them. The transfer to the United States rests on the European
Commission's Standard Contractual Clauses. OpenRouter and the model provider
receive the request from our relay, not from your phone, so they see our
server's address and not yours.

The assistant reaches the model over an OpenAI-compatible interface, so anyone
who self-hosts Velorki can point their relay at any provider or at their own
model; then that operator's policy applies, not this one.

Data from Strava is never sent to the AI provider.

### Share links (Velorki Plus)

If you create a share link for a route or a ride, that route or ride, with its
track, its name and its statistics, is uploaded to our server and stored there
so that anyone with the link can open it. Heart rate, cadence and power are
left out: a shared ride carries its track and times, not what a sensor
measured. The link is public: anyone who has it
can see the content, including the start and end points of the track. Consider
that before sharing a ride that starts at your home.

A shared item is kept for **one year** and then deleted automatically. To have
it removed earlier, send the link to the contact address below and we delete
it. Viewing a shared link requires no account.

### Cloud sync (iCloud or Google Drive)

Each device syncs with at most one cloud, chosen under **Settings → Sync
with**: iCloud (iPhone and iPad with iOS 17 or later, and the web planner),
Google (the iPhone, the iPad, Android and the web planner) or off. On an
iPhone or iPad iCloud is on by default; on Android and in the browser sync
is off until you choose a cloud.

**What syncs.** Your saved routes, and your recorded rides with each ride's
track, notes, statistics, laps and the heart rate, cadence, power and
temperature recorded with it. A few settings sync as well: theme, accent
colour, map look, the rain radar's look, bar style, column side, units, and
the turn, voice and rerouting settings. In the browser with iCloud, settings
stay in the browser. Each app also writes one small Plus record into the same
cloud, described under Subscriptions.

**Some things never sync.** Routes read from Strava, and routes edited from
them, and the Strava links of rides you uploaded to Strava stay on the one
phone, as described under Strava above. The links of uploads to Ride with GPS
do not sync either; a route you import from Ride with GPS syncs as your own
route, without its Ride with GPS id. Downloaded map regions and routing tiles,
permissions, paired sensors, the voice, the language, connected accounts and
the subscription itself are not part of it.

**iCloud.** The data goes through Apple's CloudKit into your own iCloud
private database. Apple stores and transfers it, and it counts against your
iCloud storage. Apple encrypts it in transit and on its servers; with
Advanced Data Protection turned on, it is end-to-end encrypted, as described
in [Apple's iCloud data security overview](https://support.apple.com/en-us/102651).
In the browser you sign in with Apple's own button, in a window of Apple's;
Apple's CloudKit JS script is loaded from Apple only once you choose iCloud,
and keeps your Apple sign-in in a cookie on the planner's site until you sign
out (clearing the site's data in the browser removes it too).

Apple's upload server does not accept uploads sent from our site directly. So
when the web planner saves a route or a ride to iCloud, the record's file (the
route's or ride's track and details) is sent to app.velorki.com/cloudkit/upload,
a small Cloudflare function that passes it unchanged to the one-time upload
address Apple gave for it and hands Apple's receipt back. It stores nothing, and
we keep no logs of it. The record's other fields go to Apple directly.

**Google Drive.** You sign in with your Google account, and Velorki asks for
one permission only: its own hidden app folder in your Drive
(`drive.appdata`). It cannot see or change any other file in your Drive, and
the folder does not show up among your files. Google stores the data and it
counts against your Google storage; Google encrypts it in transit and on its
servers, not end to end. The phone keeps your Google account's id and email
address to show who is signed in. In the browser you sign in with Google's own
button; Google's sign-in script is loaded only once you choose Google, and its
access token lives only as long as the page and at most an hour.

**What Orkitec sees.** Nothing. Orkitec runs no server for sync and cannot
read, access or delete what is in your iCloud or your Drive; there is no
Velorki account. Apple and Google act under your own agreement with them.

**Deleting, turning it off.** While sync is on, deleting a route or a ride on
one device deletes it in your cloud and on your other devices too. Choosing
**Off**, signing out, or switching to the other cloud stops syncing on that
device and deletes nothing; switching sends your library to the new cloud and
leaves the old copy where it was. What is already in iCloud stays until you
delete it in iCloud settings on an Apple device. What is in Google Drive stays
until you delete it: in Google Drive on the web, Settings → Manage apps →
Velorki → Options → Delete hidden app data; removing Velorki's access at
myaccount.google.com/permissions stops it reaching the folder.

### Subscriptions

Velorki Plus is sold through the App Store and Google Play, and handled by
RevenueCat on our behalf. RevenueCat assigns your installation an **anonymous
app user id**, a random string that is not linked to a name, an email address
or a device identifier. RevenueCat also receives the purchase receipt from the
store. Our relay sends that anonymous id to RevenueCat to check whether your
subscription is active, and to nothing else.

We never see your payment details; those stay with Apple or Google.

**Plus in the browser.** Plus cannot be bought in the web planner. To use Plus
bought in a phone app there, each app that syncs writes one record of its own
into the cloud it syncs with: its RevenueCat app user id, whether it is an
iPhone or Android app, whether its store last said Plus is active, and when it
last wrote, under a random id for the device. It writes it again every six
hours and when Plus starts or ends. The web planner, signed in to the same
iCloud or Google account, reads these records, keeps them in the browser, and
sends the freshest one's id to our relay with each Plus request, exactly as the
app would. The relay checks that id with RevenueCat as it does for the apps;
the browser does not contact RevenueCat, makes no id of its own for Plus and
never writes a Plus record.

The record goes only into the account sync first ran with, or one you then
choose under Settings → Sync with: after a sign-out, another account or sync
switched off, the app stops writing it and never copies it into a second
account on its own. It is not deleted from the cloud; the web planner ignores
a record not written for 30 days, and forgets the records it kept when you
sign out or change account or cloud.

### Update notices and ratings

A few seconds after launch, and again after a day in the background, the app
asks its store whether a newer version exists. On iOS it asks Apple's public
App Store lookup (`itunes.apple.com`) with Velorki's bundle id and your
phone's country and language codes; on Android it asks Google Play's in-app
update service on the phone, which answers only for an install from Play. Each
involves your IP address, as any web request does, and nothing else of yours.

From time to time the app asks the system to show its own rating sheet. Apple
or Google decide whether it appears and how often; a rating or review you give
there goes to them under your store account, and the app is not told whether
you rated or what. The web planner does neither.

### Crash reporting and analytics

There is none. The app contains no crash reporting, no analytics and no
advertising SDK, and it sends no usage statistics; every network request it
makes is one of those described above. Crashes are reported by the app stores
in aggregate to the developer account, without anything that identifies you,
and only if you have that switched on in your phone's own settings. If a crash
reporter is ever added, this section will name it and say what it collects
before that version ships.

### Server logs

Our relay and our routing server keep operational logs (request time, endpoint,
status, IP address, and a client version header) to run the service, to find
faults and to apply rate limits. They are not used to build profiles of users,
and they never contain an access token, a request body or a subscriber id.

- The web server's access logs are kept on the machine for **14 days** and then
  deleted by log rotation.
- The application's own log lines are collected by Orkify, the deployment
  dashboard the operator runs on the same Hetzner infrastructure, and are purged
  there after **90 days** at the latest.

## This website

velorki.com is a plain website: no account, no advertising, no analytics, no
tracking. Nothing you do here is measured, so the notice you may have seen at
the bottom of the page is exactly that, a notice: there is no consent to give or
to refuse, because nothing is stored on your device until you ask for it. The
🍪 Cookies entry in the footer brings it back.

- **Server logs.** Every request is logged as described under Server logs
  above: time, path, status, size, your IP address and your browser's user
  agent, kept 14 days.
- **Error reports.** If a page of this site fails in your browser, it sends
  the error, the page address and your browser's user agent to our server,
  only so we can fix the bug.
- **Cloudflare.** The site is served through Cloudflare, which terminates the
  connection, filters attacks and passes the request on to our server. It
  therefore processes your IP address and the request itself. Cloudflare is in
  the United States; the transfer rests on the EU Standard Contractual Clauses.
- **A language cookie.** Picking a language in the header sets a cookie called
  `NEXT_LOCALE` (the language code you chose, such as `en`, one year). It exists so the site opens
  in the language you chose. Nothing else is stored in it, and it is only set
  when you make that choice — it is strictly necessary for a function you asked
  for and needs no consent under section 25 (2) TDDDG.
- **A theme preference.** Choosing light, dark or an accent colour writes
  `velorki.theme` into your browser's local storage. It never leaves the
  browser and is not readable by us. Dismissing the notice above writes one
  more key, `velorki.cookie-notice`, so it is not shown again.
- **Share pages.** Opening a `velorki.com/s/…` link loads the shared route from
  our server and the map tiles from OpenFreeMap, which sees your IP address as
  any web request does. The page has no other third-party content.
- **The support chat.** The chat button in the corner is Orkify's widget.
  Orkitec runs Orkify as well, so it is our own infrastructure, but it is a
  different site: the script is loaded from orkify.com and asks orkify.com for
  its settings when the page opens, which means your IP address reaches it as it
  reaches any server you make a request to. Nothing else happens until you open
  the chat.

  When you do write to us, your message — and the name and email address you
  type into its form — is delivered to a private Discord channel where we
  answer, and the conversation stays there until we delete it. Ask at
  ride@velorki.com and we remove yours. The widget keeps the conversation's id
  and the name and email you gave in your browser's local storage, so a reply
  still finds you when you come back, and clears them when you end the chat. If
  you open the sticker picker, your search goes to Klipy, which returns the
  images. Do not put anything into the chat you would not want in a support
  ticket; for a security report, use the address in
  [SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md)
  instead.
- **Fonts and images** all come from this server, and apart from the support
  chat there is no third-party script, no CDN for our own assets and no font
  service.

## The web planner (app.velorki.com)

app.velorki.com is the same app running in your browser: it plans, searches
and keeps a library, but does not record or navigate. There is no account, no
analytics and no advertising. On a phone or tablet the address shows the app
download page and loads nothing else.

- **Stored in your browser.** Your routes, rides and settings are kept in a
  database in the browser's own storage (IndexedDB, or the Origin Private File
  System in some browsers), the routing tiles and search indexes you
  downloaded in its Cache Storage, and settings, the cloud account you signed
  in to and an anonymous id like the app's in its local storage. They stay in
  that browser, on that computer, until you delete them in the planner or clear
  the site's data in the browser. This storage is what the planner is for, so
  it needs no consent under section 25 (2) TDDDG.
- **What it contacts.** The same services as the app, under the same rules as
  above: map tiles from OpenFreeMap (and CyclOSM if you turn it on), Photon
  for an online search, the public weather services for the weather layers,
  and our relay for the AI assistant, Plus weather and share links. It never
  uses the routing server: routes are computed in the browser. Routing tiles
  come through app.velorki.com. When a text needs a script the app's own fonts
  lack, the browser loads a fallback font from Google Fonts
  (`fonts.gstatic.com`), which sees your IP address. Cloud sync contacts Apple
  or Google, only once you choose one.
- **Cloudflare.** The planner is served by Cloudflare Pages. Two small
  functions there answer `/tiles/` (fetching the tiles from our GitHub mirror)
  and `/cloudkit/upload` (see Cloud sync). Like any server they see your IP
  address and the request; they store nothing, and we keep no logs of them.

## Retention and deletion

| Data | Kept | How to delete it |
|---|---|---|
| Routes, rides, settings, offline data | on your phone, until you delete them | delete them in the app, or uninstall the app (with sync on, deleting a route or ride deletes it in your cloud too) |
| Strava / RideWithGPS tokens | on your phone, encrypted so that only our relay can open them, until you disconnect; never stored on our side | disconnect in the app, or uninstall |
| Strava data: your name, activity links | on your phone, until you disconnect; never stored on our side | disconnect Strava in the app, or uninstall; questions to ride@velorki.com |
| Routes imported from Strava, and routes edited from them | on your phone, only while the route still exists on Strava: checked again every 48 hours, removed if it was deleted there or could not be checked for 7 days; never stored on our side | delete it in the app, disconnect Strava, or uninstall |
| The cached list of your Strava routes | on your phone, at most 48 hours | disconnect Strava, or uninstall |
| Rate-limit counters (anonymous install id, IP address) | on our server, for the counting window, at most one day | not applicable |
| Share links | one year, then deleted automatically | delete them from the app |
| Routes, rides and settings synced through iCloud | in your own iCloud, until you delete them there; never stored on our side | delete them in iCloud settings on an Apple device |
| Routes, rides and settings synced through Google Drive | in your Drive's hidden Velorki folder, until you delete it; never stored on our side | in Google Drive on the web: Settings → Manage apps → Velorki → Options → Delete hidden app data |
| Plus records (RevenueCat id, platform, Plus active, last written) | in the cloud you sync with, until you delete the app's data there; ignored by the web planner after 30 days | as the synced routes above |
| The web planner's library, tiles and settings | in your browser, until you delete them | delete them in the planner, or clear the site's data in the browser |
| AI prompts | not stored by us beyond what the logs above contain | not applicable |
| RevenueCat data | per RevenueCat's own policy | contact us and we will pass the request on |
| Support chat conversations | in our Discord channel until we delete them | ask at ride@velorki.com |

Uninstalling the app removes everything the app stored on the device. What
sync has put in your iCloud or your Google Drive stays there; see Cloud sync
above. It does
not remove share links you created (they expire after one year, or on
request), and it does not remove anything you uploaded to Strava or
RideWithGPS.

## Legal bases

For readers in the EU and the UK, the legal bases under Article 6 (1) GDPR are:

| What | Basis |
|---|---|
| Serving the website and the share pages, keeping the servers up, finding faults, rate limits, defending against attacks | (f) legitimate interest in running a service that works and is not abused |
| Online routing and online search, when you ask for them | (b) performance of the service you requested, and (f) for the coordinates strictly needed to answer |
| Velorki Plus: checking with RevenueCat that a subscription is active | (b) performance of the contract |
| Velorki Plus: the finer weather along the route and the rain radar | (b) performance of the contract |
| Strava and RideWithGPS: connecting an account, every transfer you trigger, and the Strava data kept on your phone | (b) performance of the service you requested, plus (a) consent, given by connecting the account and withdrawn by disconnecting it |
| Share links you create | (b) performance of the contract |
| Cloud sync with iCloud or Google Drive, while it is on, including the Plus records and the web planner's upload through `/cloudkit/upload` | (b) performance of the service you requested; Apple and Google act under your own agreement with them |
| The web planner: serving it, storing your library in your browser, fetching tiles through app.velorki.com | (b) performance of the service you requested, and (f) for the IP address and request strictly needed to answer |
| Update notices | (f) legitimate interest in telling you about a newer version; only the bundle id, country and language are sent |
| The AI assistant | (a) consent, asked for separately in the app and revocable in the settings |
| Answering you in the support chat | (b) where it concerns a subscription, otherwise (f) legitimate interest in answering the person who wrote to us |
| Keeping tax-relevant records of a subscription | (c) legal obligation — and Apple and Google, not we, hold the billing data |

We do not profile, we take no automated decisions about you, and we do not use
any of this for direct marketing.

## Who else receives data

We do not sell, rent or trade personal data. It reaches these parties, and no
others:

**Processors, acting for us under a data processing agreement**

- **Hetzner Cloud GmbH**, Gunzenhausen, Germany — the server that runs the
  relay, the share links and this website. Data stays in Germany.
- **Cloudflare, Inc.**, San Francisco, USA — DNS, CDN and attack protection for
  velorki.com and api.velorki.com, and hosting of the web planner at
  app.velorki.com with its `/tiles/` and `/cloudkit/upload` functions. IP
  addresses and request metadata, and the iCloud upload it passes on unread.
- **RevenueCat, Inc.**, San Francisco, USA — the subscription check. The
  anonymous app user id and the store receipt, no name and no email address.
- **Orkify**, run by the same operator on the Hetzner infrastructure above —
  the deployment dashboard that collects the application logs and process
  metrics described under Server logs and this website's error reports, and
  the support chat widget.
- **Discord Netherlands B.V.** (for users in Europe; Discord Inc., San
  Francisco, USA, for the underlying service) — where a support chat
  conversation is delivered and kept.
- **Klipy** — the sticker and GIF search in the support chat, and only while
  that picker is open.
- **OpenRouter, Inc.**, USA, and the model provider it forwards to — the AI
  assistant, only after you consented, restricted to providers that neither
  train on nor retain requests.

**Services your phone or browser contacts directly, each responsible for its
own processing**

- **OpenFreeMap** (map tiles) and **OpenStreetMap France** (the CyclOSM
  overlay, only when you switch it on) — the tiles for the part of the map you
  are looking at, and your IP address.
- **komoot GmbH**, Potsdam, Germany — the Photon geocoder at
  `photon.komoot.io`, and only for an online search you asked for.
- **OpenStreetMap** (`api.openstreetmap.org`) — a place's details, when you
  tap "Details" on its card.
- **Public weather services** — the Deutscher Wetterdienst, NOAA, Iowa State
  University, NASA, EUMETSAT, the KNMI and the Finnish Meteorological Institute
  — the part of the map or the box around your route you asked for, a time, and
  your IP address, only while a weather layer or the route's free forecast is
  on.
- **Apple Inc.** (iCloud) — the routes, rides, settings and Plus records of
  iCloud sync, in your own iCloud, and only while you sync with iCloud. We do
  not receive them; Apple acts under your own iCloud agreement with Apple.
- **Google Ireland Ltd**, Dublin (Google LLC, USA, outside the EEA and
  Switzerland) — the routes, rides, settings and Plus records of Google sync,
  in your own Drive's hidden app folder, and only while you sync with Google.
  We do not receive them; Google acts under your own Google agreement.
  Google also serves the web planner's fallback fonts (`fonts.gstatic.com`)
  and Google Play's update check on Android.
- **GitHub, Inc.**, San Francisco, USA — our tile mirror, from which the app
  downloads routing tiles and search indexes; the tile names and your IP
  address.
- **Apple Inc.** and **Google Ireland Ltd** — the sale of Velorki Plus, the
  update check and the rating sheet. They are the sellers; we never see your
  payment details.
- **Strava, Inc.** and **Ride with GPS** — only after you connect the account
  and only for a transfer you trigger. What they do with it is governed by
  their own policies.

We will also hand data to a court or an authority where the law requires it.

## Transfers outside the EU

Cloudflare, RevenueCat, OpenRouter and the model provider behind it, Discord,
Klipy, Strava, Ride with GPS, GitHub, Apple and Google are in the United States or
transfer data there. Those transfers rest on the European
Commission's Standard Contractual Clauses, or on the provider's certification
under the EU–US Data Privacy Framework where it has one, together with the
provider's own technical safeguards. Hetzner, komoot and the map tile services
we rely on are in the EU, OpenStreetMap in the UK. Everything the app stores
for you stays on your phone, or in your browser, and is transferred nowhere
unless you turn on sync, which goes to your own iCloud or Google Drive.

## Security

Every connection to our servers and to the services above is encrypted with
TLS. Strava and RideWithGPS tokens never sit unencrypted anywhere: your phone
holds them in the platform's secure storage, wrapped with a key only the relay
has, and the relay unwraps one for the single request it is needed for and
keeps nothing. The share database is on the server's disk, outside the release
directory, readable only by the service user. Logs are redacted: no
`Authorization` header, no request body, no subscriber id. Access to the server
requires a key, not a password, and is restricted to the operator. Should a
breach put your rights at risk, we will notify the supervisory authority within
72 hours (Article 33 GDPR) and, where the law requires it, you.

## Your rights

If you are in the EU or the UK, you have the right of access (Article 15
GDPR), rectification (16), erasure (17), restriction of processing (18), data
portability (20) and objection to processing based on a legitimate interest
(21), and where we rely on your consent — the assistant — you may withdraw it
at any time without affecting what was lawful before (Article 7 (3)). Most of
it you can exercise yourself, because the data is on your phone, in your
browser or in your own cloud, and can be exported as GPX, FIT or TCX files
whenever you like.

For anything held on our side (share links, log entries, the RevenueCat record)
write to **ride@velorki.com**. We answer within 30 days. We will need enough
information to identify the data, which for a share link means the link itself,
since there is no account to look you up by.

You may also complain to a supervisory authority. Ours is the
[Berliner Beauftragte für Datenschutz und Informationsfreiheit](https://www.datenschutz-berlin.de),
and you may equally go to the authority where you live.

The controller is Steffen Roemer, trading as "Orkitec", Straße der Pariser
Kommune 27, 10243 Berlin, Germany.

## Children

Velorki is not directed at children and does not knowingly collect data from
them. It has no social features, no user-to-user messaging and no advertising.

## Changes

Changes to this policy are published on this page, with the date at the top
changed; significant ones are also announced on the website. Old versions
remain in the repository's git history.

## Contact

Orkitec, ride@velorki.com; postal address in the [imprint](./imprint). For
security reports see
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) in the
source repository.
