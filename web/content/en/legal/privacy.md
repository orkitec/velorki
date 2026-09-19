---
title: Privacy policy
description: "What Velorki does with your data: no account, routes and rides stay on your phone, and a list of exactly what leaves the device and when."
draft: true
---

> **This is a draft.** It describes what the app is designed to do. It has not
> been reviewed by a lawyer, and it must be before it is published as the
> privacy policy of a released app. Some points below are still marked "to be
> decided".

Effective date: to be set at launch.

Velorki is a bike route planning and ride recording app made by Orkitec. This
page explains what happens to your data.

## The short version

- There is **no account**. You do not sign up, and we do not know who you are.
- Your routes, your rides and your settings stay **on your phone**.
- Some things need a server: map tiles, routing outside the areas you have
  downloaded, search when you ask for it, and, if you use them, the AI
  assistant, the Strava and RideWithGPS connections, and share links. Each is
  described below.
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
with a ride only where the ride does: in a GPX or FIT file you export, or in an
upload to Strava or RideWithGPS that you start.

If you connect Strava or RideWithGPS, the access tokens for those accounts are
stored in the phone's secure storage (Keychain on iOS, Keystore on Android) and
stay there.

On Android, the app is excluded from Google's cloud backup and from
device-to-device transfer, so your rides and your access tokens are not copied
off the phone by the system either. Moving to a new phone means exporting what
you want to keep as GPX or FIT files.

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
exchanges it for an access token by adding our application secret, and gives
the token back to the app. We do not store the token; your phone does. After
that, your phone talks to Strava and to RideWithGPS **directly** with your own
token. Your rides and routes do not pass through our servers.

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
- if you ask for a route description, a short summary of the route (distance,
  ascent, surface shares).

No identifier of you or your phone is put into the prompt. The model returns a
structured request: a distance, a shape, place names, preferences. The actual
routing then happens in the app; the model never sees your route.

Our AI provider is **OpenAI (or the provider configured by the operator)**.
The assistant runs on a hosted model that our relay reaches over an
OpenAI-compatible interface: the official Velorki build sends prompts to
OpenAI, and anyone who self-hosts Velorki can point the relay at a different
provider or at their own model, in which case that operator's policy is the
one that applies. We do not permit the provider to train models on this data,
where that is offered as an option. The provider's jurisdiction is **to be
filled in before publication**, together with the legal basis for the
transfer.

Data from Strava is never sent to the AI provider.

### Share links (Velorki Plus)

If you create a share link for a route or a ride, that route or ride, with its
track, its name and its statistics, is uploaded to our server and stored there
so that anyone with the link can open it. The link is public: anyone who has it
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

### Crash reporting

**To be decided.** No crash reporting or analytics SDK is included at the time
of writing. If one is added, this section will name it and say what it collects
before the feature ships.

### Server logs

Our routing server and our relay keep operational logs (request time, endpoint,
status, IP address, and a client version header) to run the service and to
apply rate limits. The retention period for these logs is **to be decided**.
They are not used to build profiles of users.

## Retention and deletion

| Data | Kept | How to delete it |
|---|---|---|
| Routes, rides, settings, offline data | on your phone, until you delete them | delete them in the app, or uninstall the app |
| Strava / RideWithGPS tokens | on your phone, until you disconnect | disconnect in the app, or uninstall |
| Share links | one year, then deleted automatically | delete them from the app |
| AI prompts | not stored by us beyond what the logs above contain | not applicable |
| RevenueCat data | per RevenueCat's own policy | contact us and we will pass the request on |

Uninstalling the app removes everything the app stored on the device. It does
not remove share links you created (they expire after one year, or on
request), and it does not remove anything you uploaded to Strava or
RideWithGPS.

## Your rights

If you are in the EU or the UK, the GDPR gives you the right to access, correct
and delete your personal data, to restrict or object to its processing, and to
receive it in a portable form. Most of that you can exercise yourself, because
the data is on your phone and can be exported as GPX or FIT files at any time.

For anything held on our side (share links, log entries, the RevenueCat
record) write to **ride@velorki.com**. We will need enough information to
identify the data, which for share links means the link itself, since we have
no account to look you up by. You also have the right to complain to your data
protection authority.

The controller is Orkitec. Postal address and any data protection
representative: **to be filled in before publication.**

## Children

Velorki is not directed at children and does not knowingly collect data from
them. It has no social features, no user-to-user messaging and no advertising.

## Changes

If this policy changes in a way that affects what leaves your device, the app
will tell you the next time you open it, and the date at the top will change.
Old versions remain in the repository's git history.

## Contact

Orkitec, ride@velorki.com. For security reports see
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) in the
source repository.
