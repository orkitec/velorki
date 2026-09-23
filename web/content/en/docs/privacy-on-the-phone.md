---
title: Privacy on the phone
description: "In rider's terms: what stays on your phone, what leaves it, when, and to whom. There is no account and nothing is uploaded unless you ask."
order: 15
---

Velorki has no account, so there is nothing to log in to and nothing about you on a server. This page is the plain-language version of what that means in practice; the [privacy policy](/privacy) is the formal one.

## What stays on the phone

Everything you make and everything you download:

- planned routes, recorded rides and their GPS tracks,
- your settings, including which units and which voice you chose, and the weight, year of birth, sex, maximum heart rate, bike weight, bike type and threshold power you may enter under Settings → Rider, which are settings on the phone and are never sent anywhere,
- downloaded offline map areas,
- downloaded routing tiles and the place-search indexes that come with them,
- the access tokens for Strava and Ride with GPS if you connect them, which go into the phone's secure storage in a form only the Velorki relay can open.

None of it is uploaded anywhere unless you ask for it.

On Android, Velorki is deliberately left out of Google's cloud backup and out of device-to-device transfer, so your rides do not get copied off the phone by the system either. Moving to a new phone means exporting what you want to keep as GPX or FIT files, see [import and export](./import-and-export).

## What leaves the phone, and when

### While you look at the map

Map tiles are fetched from OpenFreeMap, and from CyclOSM if you turn the cycling overlay on. Asking for a tile tells the tile server which square of the world you are looking at, and involves your IP address, as any request does. An area you have downloaded is served from the phone and asks for nothing.

### While you plan

Routing happens on your phone wherever you have the routing tiles. For an area you have not downloaded, the waypoints go to a routing server, which sends the route back. It gets the waypoints, nothing else: no identity, no other routes, no rides.

**Settings → Advanced → Routing → On device only** switches the server off entirely; Velorki then offers the download instead of routing.

### While you search

Search is answered on the phone wherever the area's index is downloaded, and nothing you type leaves the device.

It goes online when you tap **Search online for "…"**, or when you have no index for the area you are looking at. Then what you typed goes to Photon, together with a rough position so that nearby results come first.

### While you record

Nothing at all leaves the phone. Recording, the statistics, the charts and the splits are all computed on the device. The same goes for heart rate, cadence and power from a watch, a Bluetooth sensor or your health app: they are stored with the ride and, if you have switched Health on, exchanged with Apple Health or Health Connect on the phone itself.

### When you ask the assistant

Only with your consent, and only what you allowed: your text, optionally a position rounded to about a kilometre, your language and unit settings. No name, no account, no route history, and never your track. See [assistant](./assistant).

### When you connect Strava or Ride with GPS

Nothing goes to either until you connect the account and then ask for something, an upload or an import.

Connecting hands a one-time code to the Velorki relay, which turns it into an access token by adding our application secret, and gives the token to your phone wrapped, so that only the relay can open it. We do not keep the token. After that every upload and import passes through the relay: it checks your subscription, counts the transfer, opens the token for that one request and forwards it to Strava or Ride with GPS. It keeps neither the file nor the token, and cannot use the token on its own.

### When you make a share link

That route or ride, with its track, its name and its figures, is copied to our server so the link can be opened. The link is public to anyone who has it, it shows where the track starts and ends, and it is deleted automatically after a year. See [sharing](./sharing).

### When you buy Velorki Plus

The store handles the payment and we never see your card. The subscription is checked against an anonymous random id that is not linked to a name, an email address or a device identifier.

## What Velorki never does

- No account, no sign-up, no email address.
- No advertising, no ad SDK, no profiling.
- No analytics or crash-reporting SDK in the app at the time of writing. If one is ever added, the privacy policy will name it and say what it collects before it ships.
- No selling of data, to anyone, ever.
- No social features and no user-to-user messaging.

## Getting rid of things

| What | How |
|---|---|
| A route or a ride | delete it in the [library](./library) |
| Offline map areas and routing tiles | delete them in [offline data](./offline-maps-and-routing) |
| A Strava or Ride with GPS token | **Disconnect** in Settings → Connections |
| Everything the app stored | uninstall the app |
| A share link | it expires after a year; mail [hello@orkitec.com](mailto:hello@orkitec.com) with the link to have it removed sooner |

Uninstalling does not remove share links you created, and it does not remove anything you uploaded to Strava or Ride with GPS.

## Your rights

If you are in the EU or the UK, the GDPR gives you rights over your personal data. Most of them you can exercise yourself, because the data is on your phone and exports as GPX or FIT at any time. For anything on our side, which is share links, log entries and the subscription record, write to [hello@orkitec.com](mailto:hello@orkitec.com). The full statement, including the legal basis and who to complain to, is in the [privacy policy](/privacy).

## Related

- [Privacy policy](/privacy)
- [Sharing](./sharing)
- [Assistant](./assistant)
- [Strava and Ride with GPS](./strava-and-ridewithgps)
- [Offline maps and routing](./offline-maps-and-routing)
