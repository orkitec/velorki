---
title: Settings and appearance
description: Every setting in Velorki, from theme, accent and units to navigation, recording, sensors, search, offline data, connections and the server URLs.
order: 14
---

The Settings tab is one scrolling page with a section per subject. This page walks it from top to bottom, so you can find the switch you are after and know what it does.

## Appearance

**Theme**: **System**, **Light** or **Dark**. System follows the phone.

**Map**: how the map itself is drawn, independently of the app's theme: **Follows theme**, **Light**, **Night** or **Black**. **Black** is the one for a dark ride with the display dimmed, and it is what battery saver forces anyway.

**Cycling overlay on dark maps**: what to do with the CyclOSM overlay when the map underneath is dark: **Inverted**, **Dimmed** or **Unchanged**. The overlay is drawn for a light background, so on a night map it needs help. This row only appears in builds that ship the overlay.

**Accent**: four colour presets: **Volt**, **Ember**, **Glacier** and **Berry**. The accent colours the buttons, the charts and the route line on the map.

**Units**: **Metric** or **Imperial**, used by every figure, slider, chart axis, turn banner and spoken cue in the app. Until you choose, Velorki follows the phone's country.

## Navigation

The three switches here are the same ones as on the Record tab's sheet.

**Turn directions**: "Show the next turn while you record along a route". The master switch; the rest of the section is greyed out while it is off.

**Voice**: "Say the turns out loud".

**Speaking voice**: which voice says them. Opens the voice list, described in [turn-by-turn navigation](./navigation).

**Announce turns** is a slider in seconds. The hint reads "12 seconds before the turn at your speed, never closer than 50 metres". Counting in seconds means the cue comes at the same moment whether you are climbing or descending.

**Re-route when off course**: "Plan a new way back onto the route when you leave it". Off means you still get told you are off route, but nothing is recomputed.

## Recording

**GPS precision**: **Battery saver**, **Normal** or **Precise**, with the hint "Precise is for trails; Normal is enough for roads". It decides how hard the one GPS client is driven while a ride runs.

**Battery saver**: "Dark map, no animations, a plain page with the numbers after 30 s; the screen is what drains the battery". The full behaviour is in [recording a ride](./recording-a-ride).

## Sensors

**Apple Health**, or **Health Connect** on Android: "Heart rate from your watch or any app that writes it; rides are saved as workouts". Turning it on is what asks the phone for access to your health data, and refusing leaves it off.

**Save rides to Health**: writes each finished ride into the store as a cycling workout. It can be switched off on its own and does nothing while the switch above it is off.

**Apple Watch**: "Heart rate from the watch, ride controls on the wrist". The row is there only on an iPhone that has a watch paired to it. Turning it on asks once to post notifications, for the "Ride started from your watch" notice. Below it, **Rest the sensor while paused**: "For rides with many stops: the watch stops measuring at every pause and the phone wakes it when you ride on". Off, the watch keeps measuring through a pause, which is what keeps it listening for the resume.

**Bluetooth sensors**: "Heart-rate straps, speed and cadence sensors, power meters", or how many sensors are paired. It opens the screen where **Scan** looks for them. All of it is walked through in [sensors and your watch](./sensors-and-watch).

## Subscription

**Velorki Plus** with **Active** or **Not active** under it, and the renewal or end date when there is one. Tapping it opens the subscription page. Underneath sit **Manage**, which opens the store's subscription page, and **Restore purchases**. See [Velorki Plus](./velorki-plus).

## Connections

One row for **Strava** and one for **Ride with GPS**, each showing **Not connected**, your name once connected, or **Not available in this build**. **Connect with Strava** and **Connect with Ride with GPS** sit under the unconnected ones, **Disconnect** beside the connected ones. See [Strava and Ride with GPS](./strava-and-ridewithgps).

## AI assistant

**What is sent** always says which consent you gave: "You have not been asked yet.", "Nothing. The assistant is switched off.", "Your text only." or "Your text and your rough position (about 1 km)." **Change** beside it reopens the consent dialog.

**Report AI output**: "Tell us about an answer that was wrong or inappropriate." Opens a mail to us.

## Advanced

**Offline data**: "Maps and routing data for rides without a signal". When the mirror has rebuilt tiles you hold, the subtitle turns orange and counts them. See [offline maps and routing](./offline-maps-and-routing).

**Search**: "What offline search shows, and in which order. Drag to change the priority." See [search](./search).

**Routing**, where routes are computed:

- **Automatic**: "On this device wherever the tiles are downloaded, on the routing server everywhere else." This is the sensible default.
- **On device only**: "Never ask the routing server. Routes outside the downloaded tiles offer the download instead."
- **Server only**: "Always ask the routing server, even where tiles are downloaded."

**Server URLs**: three fields, **BRouter URL**, **Photon URL** and **API URL**, for pointing this installation at your own servers: "Leave a field empty to use the address this build ships with." **Reset to defaults** clears all three. Most riders never touch this; it exists because Velorki is open source and you are allowed to run your own.

## About

- **Velorki**, with the version number.
- **© OpenStreetMap contributors**.
- **Open-source licences**: "The software and the map data Velorki is built on."
- **Privacy policy** and **Terms of use**, which open in the browser.
- **Report a problem**: "Open an issue on GitHub."

## Related

- [Getting started](./getting-started)
- [Turn-by-turn navigation](./navigation)
- [Recording a ride](./recording-a-ride)
- [Sensors and your watch](./sensors-and-watch)
- [Offline maps and routing](./offline-maps-and-routing)
- [Privacy on the phone](./privacy-on-the-phone)
