---
title: Getting started
description: Install Velorki, understand the four tabs, see which permissions it asks for and why, and set your units. No account is needed.
order: 1
---

Velorki is a free, open-source bike route planner and ride recorder for iPhone and Android, built on OpenStreetMap data. This page covers the first ten minutes: installing it, what it asks for, how the app is laid out, and the one setting most riders want to change straight away.

## What you need

- An iPhone running iOS 15 or newer, or an Android phone running Android 8.0 or newer.
- No account. Velorki has no sign-up, no login and no password. Nothing is stored about you on a server.
- No connection, once you have downloaded an area. Planning, routing, place search, navigation and recording all run on the phone.

## Install it

1. Install Velorki from the App Store or Google Play, the same as any other app.
2. Open it. There is no sign-up screen and no tour to click through; the app opens on the map.

Velorki is open source. If you would rather build it yourself, or run your own servers for the parts that use them, the code and the instructions are at [github.com/orkitec/velorki](https://github.com/orkitec/velorki).

## First launch

Velorki opens on the **Plan** tab, showing a world map. Nothing is downloaded yet and no permission has been asked for yet.

A good first session:

1. Move the map to where you ride and pinch to zoom in.
2. Tap the map to set a start, tap again to add a destination. A route appears within a moment.
3. Tap the download button on the right of the map (**Offline data**) and download the area, so that the map and the routing keep working when the signal does not. See [offline maps and routing](./offline-maps-and-routing) for what the two downloads are and how large they get.
4. Set your units under **Settings → Appearance → Units** if the app guessed wrong.

## The permissions it asks for, and why

Velorki asks for nothing at launch. Each permission is requested at the moment it is first needed, and each one is explained before the system dialog appears.

### Location

Asked the first time you tap **Show my position**, start a ride, or ask for a loop from where you are.

Velorki shows its own dialog first, titled **Show your position?**: "Velorki uses your location to centre the map on you and to record rides. The position stays on this device; it is never uploaded." You can answer **Not now** and keep using the app; only the features that need to know where you are stop working.

"While using the app" is enough. On Android, Velorki deliberately does **not** ask for background location: ride recording runs as a foreground service with a notification instead. On iOS, "When In Use" plus the background location mode covers a recorded ride with the screen off.

### Notifications (Android)

Asked the first time you start a ride. The recording runs inside a notification that shows your distance and time, and Android stops the recording if that notification cannot be posted. If you refuse, Velorki says so: "Without the notification permission Android stops the recording when you leave the app."

### Battery optimisation (Android)

Asked once, ever, the first time you start a ride: **Keep recording in the background**: "Android may stop the recording while the phone sleeps. Letting Velorki ignore battery optimisation keeps the track complete. You are asked only once." Answer **Allow** or **Not now**; it is never asked again.

### Files

No standing permission. When you import a GPX or FIT file, the system file picker hands that one file to the app; when you export, the system share sheet takes it away again.

Velorki asks for nothing else. There is no contacts, photos, microphone, health or advertising access anywhere in the app.

## The four tabs

The bar at the bottom has four tabs.

| Tab | What lives there |
|---|---|
| **Plan** | The map, the place search, the route planner, smart loops and the assistant. |
| **Record** | Starting, pausing and finishing a ride, the live figures, and your recent rides. |
| **Library** | Everything you saved: **Routes** and **Rides**, with import and export. |
| **Settings** | Appearance and units, navigation and recording options, offline data, search, connections, subscription and the legal pages. |

The bar floats over the content, so lists scroll underneath it.

## Units

Velorki shows distances in kilometres and metres, or in miles and feet, and it uses your choice everywhere: the stats, the sliders, the chart axes, the turn banner and the spoken cues.

1. Open **Settings**.
2. Under **Appearance**, find **Units**.
3. Choose **Metric** or **Imperial**.

Until you choose, Velorki follows the phone's country: imperial only where the country uses it, metric everywhere else.

## Where things are

- **The map controls** sit in a column on the right of the map: show my position, the cycling overlay, offline data, zoom in and zoom out. While a ride is recording a compass button joins them, which swaps between **North up** and **Map turns with you**.
- **The search field** is at the top of the Plan tab.
- **The bike profile** (Touring, Road, Gravel, MTB, Direct) is the row of chips under the search field.
- **The route sheet** is the panel at the bottom of the Plan tab. Drag it up for the elevation profile and the surface breakdown, down to see more map.

## Related

- [Planning a route](./planning-a-route)
- [Offline maps and routing](./offline-maps-and-routing)
- [Recording a ride](./recording-a-ride)
- [Settings and appearance](./settings-and-appearance)
- [Privacy on the phone](./privacy-on-the-phone)
