---
title: Getting started
description: Install Velorki, understand the four tabs, see which permissions it asks for and why, and set your units. No account is needed.
order: 1
---

Velorki is a free bike route planner and ride recorder for iPhone and Android, built on OpenStreetMap data. It runs on your phone with no account, keeps your routes and rides with you or in your own cloud, and its code is open, so anyone can check that. This page covers the first ten minutes: installing it, what it asks for, how the app is laid out, and the one setting most riders want to change straight away.

## What you need

- An iPhone running iOS 15 or newer, or an Android phone running Android 8.0 or newer.
- No account. Velorki has no sign-up, no login and no password. Nothing is stored about you on a server.
- No connection, once you have downloaded an area. Planning, routing, place search, navigation and recording all run on the phone.

## Install it

1. Install Velorki from the App Store or Google Play, the same as any other app.
2. Open it. There is no sign-up screen and no tour to click through; the app opens on the map.

Velorki is open source. If you would rather build it yourself, or run your own servers for the parts that use them, the code and the instructions are at [github.com/orkitec/velorki](https://github.com/orkitec/velorki).

## First launch

Velorki opens on the **Plan** tab. The first time, it asks for your location before anything else (see below), then shows the map where you are, or over your phone's country if you decline. Bike lanes and [stops](./stops-on-the-map) are already drawn; turn them off in **Layers** if you would rather not see them. Nothing is downloaded yet.

The empty plan says "Search for a place or tap the map." A short animation points at that line, at the search field and, if your area is not downloaded, at the download chip. It plays once and stops at your first touch.

A good first session:

1. Move the map to where you ride and pinch to zoom in.
2. Tap the map to set a start, tap again to add a destination. A route appears within a moment.
3. Download the area, so that the map and the routing keep working when the signal does not: tap **Download** in the chip over the map, or the round download button on the right of the map. Confirm the one question it asks and watch the progress in the chip. See [offline maps and routing](./offline-maps-and-routing) for what the two downloads are and how large they get.
4. Set your units under **Settings → Appearance → Units** if the app guessed wrong.

## The permissions it asks for, and why

Velorki asks for your location when you first open it, and for everything else at the moment it is first needed. Each permission is explained before the system dialog appears.

### Location

Asked when you first open the app, and after that the first time you tap **Show my position**, start a ride, or ask for a loop from where you are.

Velorki shows its own dialog first, titled **Show your position?**: "Velorki uses your location to centre the map on you and to record rides. The position stays on this device; it is never uploaded." Tap **Continue** for the system dialog. On Android you can also answer **Not now** and keep using the app; only the features that need to know where you are stop working. On iPhone the dialog has only **Continue**, and the system dialog that follows is where you decide. Refused at the first start, the map opens over your phone's country, and Velorki does not ask again until you tap **Show my position**.

With the permission given, the map opens where you left it and then glides to your position: at once to where the phone last knew you were if that is under an hour old, and to the first fresh fix when it is not, or when that fix puts you more than about 300 m from there, both when the app starts and when you come back to it after half an hour or more. It stays put while a plan is on the Plan tab, a route or ride card is open, a ride is being recorded, you are already in view, or you have moved the map yourself.

"While using the app" is enough. On Android, Velorki deliberately does **not** ask for background location: ride recording runs as a foreground service with a notification instead. On iOS, "When In Use" plus the background location mode covers a recorded ride with the screen off.

### Notifications (Android)

Asked the first time you start a ride. The recording runs inside a notification that shows your distance and time, and Android stops the recording if that notification cannot be posted. If you refuse, Velorki says so: "Without the notification permission Android stops the recording when you leave the app."

### Battery optimisation (Android)

Asked once, ever, the first time you start a ride: **Keep recording in the background**: "Android may stop the recording while the phone sleeps. In the battery settings that open, pick Velorki and allow unrestricted battery use (on some phones: not optimised), and the track stays complete. You are asked only once." Answer **Open settings** or **Not now**; it is never asked again.

### Files

No standing permission. When you import a GPX, FIT or TCX file, the system file picker hands that one file to the app; when you export, the system share sheet takes it away again.

Velorki asks for nothing else. There is no contacts, photos, microphone, health or advertising access anywhere in the app.

## The four tabs

The bar at the bottom has four tabs.

| Tab | What lives there |
|---|---|
| **Plan** | The map, the place search, the route planner, smart loops and the assistant. |
| **Record** | Starting, pausing and finishing a ride, the live figures, and your recent rides. |
| **Library** | Everything you saved: **Routes** and **Rides**, with import and export. |
| **Settings** | A list of pages: Sync, Velorki Plus and Connections; Navigation, Recording, Rider & bike and Sensors; Appearance (theme, units, language), AI assistant, Maps & data (offline data, search) and About with the legal pages. |

The bar floats over the content, so lists scroll underneath it.

## Units

Velorki shows distances in kilometres and metres, or in miles and feet, and it uses your choice everywhere: the stats, the sliders, the chart axes, the turn banner and the spoken cues.

1. Open **Settings**.
2. Under **Appearance**, find **Units**.
3. Choose **Metric** or **Imperial**.

Until you choose, Velorki follows the phone's country: imperial only where the country uses it, metric everywhere else.

## Where things are

- **The map controls** sit in a column on the right of the map: **Show my position**, **Layers** ([the cycle map](./map-layers) and [stops on the map](./stops-on-the-map)), **Offline data** (the download button; not on a small screen such as an iPhone SE), **Zoom in** and **Zoom out**. On the Record tab a compass button joins them, which swaps between **North up** and **Map turns with you**.
- **The search field** is at the top of the Plan tab.
- **The bike profile** (Touring, Road, Gravel, MTB, Direct) is the row of chips under the search field.
- **The route sheet** is the panel at the bottom of the Plan tab. Drag it up for the elevation profile and the surface breakdown, down to see more map.
- **A sheet over the map**, such as Layers, a place's card, a point's sheet or the loop sheet, sends the tab's card down to its lowest height while it is open; it comes back up when the sheet closes.

## Related

- [Planning a route](./planning-a-route)
- [Offline maps and routing](./offline-maps-and-routing)
- [Recording a ride](./recording-a-ride)
- [Settings and appearance](./settings-and-appearance)
- [Privacy on the phone](./privacy-on-the-phone)
