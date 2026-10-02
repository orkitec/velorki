---
title: Privacy policy
description: "What Velorki does with your data: no account, routes and rides stay on your phone, and a list of exactly what leaves the device and when."
draft: false
---

Effective date: 30 September 2026.

Velorki is a bike route planning and ride recording app made by Orkitec. This
page explains what happens to your data.

**Who is responsible.** The controller for everything described here is Steffen
Roemer, trading as "Orkitec", Straße der Pariser Kommune 27, 10243 Berlin,
Germany, ride@velorki.com. No data protection officer is appointed: the
processing described below does not require one under Article 37 GDPR. The full
provider details are on the [imprint](./imprint) page.

## The short version

- There is **no account**. You do not sign up, and we do not know who you are.
- Your routes, your rides and your settings stay **on your phone**.
- Some things need a server: map tiles, routing outside the areas you have
  downloaded, search when you ask for it, and, if you use them, the AI
  assistant, the Strava and RideWithGPS connections, and share links. Each is
  described below.
- This **website** has no analytics, no advertising and no tracking, so the
  short notice at the bottom of it asks nothing of you.
- We do not sell your data, and we do not use it for advertising or profiling.

## What stays on your device

Planned routes, recorded rides, their GPS tracks, your settings, downloaded
offline map regions, downloaded routing tiles and the place-search indexes that
come with them are stored in the app's own storage on your phone. They are not
uploaded anywhere unless you ask for it.

Heart rate, cadence and power from an Apple Watch, a Bluetooth sensor or your
health app are stored with the ride, on the phone, like the track itself. With
the Health switch on in Settings, the app reads heart rate from Apple Health or
Health Connect and writes your finished rides there as cycling workouts; that
exchange happens on your phone and none of it reaches us. Sensor values travel
with a ride only where the ride does: in a GPX, FIT or TCX file you export, or in an
upload to Strava or RideWithGPS that you start.

If you connect Strava or RideWithGPS, the access tokens for those accounts are
stored in the phone's secure storage (Keychain on iOS, Keystore on Android), in
an encrypted form that only our relay can open; see the Strava and RideWithGPS
section below.

On Android, the app is excluded from Google's cloud backup and from
device-to-device transfer, so your rides and your access tokens are not copied
off the phone by the system either. Moving to a new phone means exporting what
you want to keep as GPX, FIT or TCX files.

## What leaves your device, and when

### Routing

Routing normally happens entirely on your phone, from routing tiles you have
downloaded, and nothing is sent anywhere. For an area you have no tiles for,
the app sends the coordinates of your waypoints to a routing server (BRouter,
run by us) which sends back the route. It needs the waypoints to compute the
route; it does not receive your identity, your other routes or your rides.

### Search

Places are searched on your phone, in the search indexes that come with the
routing tiles you downloaded. Nothing you type there leaves the device.

If you tap "Search online for …" at the bottom of the results (or if you have
downloaded no routing tiles, in which case the search box goes online straight
away), what you typed is sent to Photon, a geocoding service, together with a
rough position so that nearby results rank first. Photon returns place
suggestions.

### Map tiles

The map is drawn from tiles fetched from OpenFreeMap, and from CyclOSM if you
turn the cycling overlay on. Fetching a tile tells the tile provider which part
of the map you are looking at, and involves your IP address, as any web request
does. Map data is © OpenStreetMap contributors.

### Strava and RideWithGPS (Velorki Plus)

Nothing is sent to Strava or RideWithGPS unless you connect the account
yourself and then trigger an action: uploading a ride, importing a route.

When you connect, the app hands a one-time code to our relay server, which
exchanges it for an access token by adding our application secret, encrypts
the token with a key only the relay holds, and gives it back to the app in that
form. Your phone stores the encrypted token; it cannot use it on its own, and
we do not store it at all.

After that, every upload, route transfer, import and disconnect you trigger
passes through the relay: it checks that your subscription is active, decrypts
the token for that one request, forwards the request to Strava or RideWithGPS
and passes the answer back to the app. It keeps neither the file nor the
token, and nothing of the answer, and it applies the same rate limiting as
every other relay call (see Server logs below). Its logs never contain the
token, the request body or the subscriber id.

What Strava or RideWithGPS then do with the data you send them is governed by
their own privacy policies.

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

### Subscriptions

Velorki Plus is sold through the App Store and Google Play, and handled by
RevenueCat on our behalf. RevenueCat assigns your installation an **anonymous
app user id**, a random string that is not linked to a name, an email address
or a device identifier. RevenueCat also receives the purchase receipt from the
store. Our relay sends that anonymous id to RevenueCat to check whether your
subscription is active, and to nothing else.

We never see your payment details; those stay with Apple or Google.

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
  `NEXT_LOCALE` (the value `en` or `de`, one year). It exists so the site opens
  in the language you chose. Nothing else is stored in it, and it is only set
  when you make that choice — it is strictly necessary for a function you asked
  for and needs no consent under section 25 (2) TTDSG.
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

## Retention and deletion

| Data | Kept | How to delete it |
|---|---|---|
| Routes, rides, settings, offline data | on your phone, until you delete them | delete them in the app, or uninstall the app |
| Strava / RideWithGPS tokens | on your phone, encrypted so that only our relay can open them, until you disconnect; never stored on our side | disconnect in the app, or uninstall |
| Share links | one year, then deleted automatically | delete them from the app |
| AI prompts | not stored by us beyond what the logs above contain | not applicable |
| RevenueCat data | per RevenueCat's own policy | contact us and we will pass the request on |
| Support chat conversations | in our Discord channel until we delete them | ask at ride@velorki.com |

Uninstalling the app removes everything the app stored on the device. It does
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
| Strava and RideWithGPS: connecting an account and every transfer you trigger | (b) performance of the contract, plus (a) consent, given by connecting the account |
| Share links you create | (b) performance of the contract |
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
  velorki.com and api.velorki.com. IP addresses and request metadata.
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
- **Apple Inc.** and **Google Ireland Ltd** — the sale of Velorki Plus. They
  are the sellers; we never see your payment details.
- **Strava, Inc.** and **Ride with GPS** — only after you connect the account
  and only for a transfer you trigger. What they do with it is governed by
  their own policies.

We will also hand data to a court or an authority where the law requires it.

## Transfers outside the EU

Cloudflare, RevenueCat, OpenRouter and the model provider behind it, Discord,
Klipy, Strava, Ride with GPS, Apple and Google are in the United States or
transfer data there. Those transfers rest on the European
Commission's Standard Contractual Clauses, or on the provider's certification
under the EU–US Data Privacy Framework where it has one, together with the
provider's own technical safeguards. Hetzner, komoot and the map tile services
we rely on are in the EU. Everything the app stores for you stays on your
phone and is transferred nowhere at all.

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
it you can exercise yourself, because the data is on your phone and can be
exported as GPX, FIT or TCX files whenever you like.

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

If this policy changes in a way that affects what leaves your device, the app
will tell you the next time you open it, and the date at the top will change.
Old versions remain in the repository's git history.

## Contact

Orkitec, ride@velorki.com; postal address in the [imprint](./imprint). For
security reports see
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) in the
source repository.
