---
title: Troubleshooting
description: "Fixes for the common problems: no position, no route, the missing tiles banner, a silent voice on iOS, stuck downloads and links that will not open."
order: 17
---

The things that go wrong most often, and what to do about each. If your problem is not here, the last section says how to report it.

## Velorki cannot find my position

The symptoms are "No position fix yet.", a locate button that does nothing, or "Turn on location or tap the map to set a start."

1. **Was the permission refused?** Velorki asks with its own dialog, **Show your position?**, before the system one. If you answered **Not now**, tap the locate button again and answer **Continue**.
2. **Is it switched off for Velorki?** "Location permission is turned off for Velorki. Enable it in the system settings." comes with a **Settings** action that takes you straight there. Grant "While using the app" or "When In Use".
3. **Are location services off on the phone?** "Location services are switched off on this device." is about the phone, not about Velorki. The **Settings** action opens the right place.
4. **Indoors, or just switched on?** "No position fix yet." often means the phone has no fix yet at all. Go outside and give it half a minute.

Velorki never needs background location. "While using the app" is enough, including for recording a ride.

## No route appears

**"This route needs routing tiles that are not on this device."** Your phone has no routing data for the area and there is no routing server to fall back on. Tap the button, which counts the tiles and their size, and download them. See [offline maps and routing](./offline-maps-and-routing).

**"No routing server configured, set one in Settings → Advanced."** This build ships no server address. Download the routing tiles for where you are and route on the phone instead.

**Settings → Advanced → Routing is on "On device only".** Then Velorki will never ask a server, by design. Switch it to **Automatic** or download the tiles.

**"Routing failed:" with a reason.** Usually the server was unreachable. Try again, and check that a waypoint has not landed in the sea or on a motorway where no bike may go. Moving the offending point a few metres onto a real road usually fixes it.

## The missing tiles banner will not go away

The banner is in the planner whenever the route crosses an area whose routing tile is not on the phone. Velorki never routes on partial coverage, because the router would treat the missing tile as empty land and quietly hand back a wrong route.

1. Tap the button on the banner. It opens **Offline routing data** with exactly the tiles the route needs already picked out.
2. Download them. Tiles are 125 to 250 MB each, so be on Wi-Fi.
3. When a tile lands, the planner routes again by itself and the banner is replaced by the route's figures.

If the tiles you need show **Update needs a newer Velorki**, update the app first; the dialog explains why.

## The voice says nothing

Check in this order:

1. **Settings → Navigation → Turn directions** on, and **Voice** on. Voice is greyed out while Turn directions is off.
2. **The mute button on the turn banner.** It silences the voice for the rest of that ride only. Tap it again.
3. **Are you following a route?** Guidance needs a route chosen under **Follow a route** on the Record tab, and a ride that is actually recording.
4. **The phone's own volume and silent switch.**

### On an iPhone

If Velorki shows **Better voices are a download away**, the phone only has the compact voice for your language. Follow the steps in the card: **Settings → Accessibility → Spoken Content → Voices → your language → tap the cloud** next to an Enhanced or Premium voice. Velorki then uses the best voice on the phone by itself.

If the chosen voice is marked **Needs internet**, it is generated on a server: with no signal the turn goes unspoken or comes late. Pick a voice without that mark for rides. They are hidden unless **Show online voices** is on at the bottom of the voice list.

"No voice for your language is installed." means the phone has nothing to speak with; add a voice in the phone's own text-to-speech or Spoken Content settings.

## A download is stuck or fails

- **Downloads only run while the app is open.** Leave Velorki in the foreground for a big tile. If it stops, the part that arrived is kept and the next attempt resumes from there.
- **"The download failed:"** with a reason. Tap the tile again to retry. A resumed download does not start from zero.
- **"The tile list could not be loaded:"** means the mirror could not be reached. **Try again** is on the screen.
- **Check the free space on the phone.** A routing tile of 250 MB needs 250 MB, and the map area on top of that.
- **Cancel and restart** with the close button in the progress header if a download has clearly stalled.
- Velorki cannot tell Wi-Fi from mobile data, so it warns rather than blocking. Start big downloads on Wi-Fi yourself.

## A share link will not open in the app

- **The link is older than a year.** Shared items are deleted automatically after 365 days, and the page then says not found. Ask for a fresh link.
- **The app is not installed on that phone.** The page still works in the browser: the map, the figures and **Download GPX**.
- **"Open in Velorki" did nothing.** Download the GPX from the page and open it with Velorki instead; it lands on the same import screen. An expired or mistyped link is ignored silently rather than showing an error.

## A file will not import

Velorki reads GPX and FIT, and decides by the bytes, not the file name.

| Message | Meaning |
|---|---|
| "That is not a GPX or FIT file." | the content is neither format, whatever the name says |
| "That file could not be read." | the file is one of the two but damaged |
| "That file has no track points." | an empty file, or a GPX with only waypoints |
| "That file could not be opened." | the system would not hand the file over |

If a file imports as the wrong kind, switch **SAVE AS** between **Route** and **Ride** on the import screen before saving. FIT courses are guessed as rides because of how their timestamps work.

## The recording stopped by itself

On Android, answer **Allow** to **Keep recording in the background** and grant the notification permission; both are what stop the system killing the recording while the phone sleeps. On either platform, the track is written continuously, so if the app was killed you get **Unfinished ride** on the next launch, with **Resume**, **Finish** and **Discard**. See [recording a ride](./recording-a-ride).

## A Bluetooth sensor is not found

1. **Wake the sensor up.** A strap transmits only with skin contact, a cadence sensor only with the crank turning. The screen says as much: "Nothing yet. Wake the sensor up: put the strap on, or turn the cranks."
2. **Switch Bluetooth on.** "Switch Bluetooth on to find your sensors." is about the phone's radio, not about the sensor.
3. **Grant the permission.** "Velorki was not allowed to use Bluetooth." means it was refused. iOS asks the first time you tap **Scan**, and only then.
4. **Free the sensor.** These sensors serve one device at a time, so a head unit or another app holding yours keeps Velorki from seeing it.
5. **Scan again.** A scan runs about fifteen seconds and lists only devices speaking the standard heart rate, speed and cadence, or power profiles.

A paired sensor that says **Not connected** is out of range, asleep or flat. Velorki keeps trying while a ride records or the **Bluetooth sensors** screen is open. See [sensors and your watch](./sensors-and-watch).

## The watch does not connect

- **There is no Apple Watch switch.** It appears in **Settings → Sensors** only on an iPhone that has a watch paired to it.
- **The watch app is not on the watch.** It ships inside the iPhone app; if it did not arrive by itself, install Velorki from the **Watch** app on the iPhone.
- **The ride is running but the watch measures nothing.** The phone can only ask a watch app that is running. Open Velorki on the watch and tap **Start ride**, which starts both ends.
- **The watch shows no pulse.** The watch asks for permission to read your heart rate the first time a workout starts there. If that was refused, grant it in the watch's own privacy settings.

## No heart rate from Health

- **The switch is off.** **Apple Health**, or **Health Connect** on Android, has to be on in **Settings → Sensors**. Nothing is read while it is off.
- **Access was refused.** "Velorki was not given access to your health data." leaves the switch off. Turn it on again and allow the heart rate, or grant it in the health app itself.
- **Nothing has written a heart rate.** Velorki only reads what is already in the store, so with no watch and no app putting a pulse there, there is nothing to read.
- **It arrives late.** The store is asked every five seconds, or every thirty with battery saver on, and the gaps are filled once more when the ride is saved. A strap or a watch reporting directly is always quicker.

## A Plus feature is missing

- **"Not available in this build"** on a connection row, or on the subscription page, means this copy of Velorki was compiled without the keys for that service or store. That is what a self-built copy looks like.
- **The Ask button or the Share link button is not there at all** in a build with no Velorki server configured.
- **Everything else** should say "… is part of Velorki Plus" and offer the subscription page. If you have a subscription and it does not, tap **Restore purchases** in **Settings → Subscription**.

## Report a bug

**Settings → About → Report a problem** opens the issue tracker, or go straight to [github.com/orkitec/velorki/issues](https://github.com/orkitec/velorki/issues).

A good report has:

1. what you did, step by step, and what happened instead of what you expected;
2. the phone and the operating system version;
3. the Velorki version, from **Settings → About**;
4. where it happened, if the map or the routing is involved, because a lot of problems are specific to one corner of the map data;
5. a screenshot, which is usually worth all of the above.

Velorki has no crash reporting and sends us nothing by itself, so a report from you is the only way we hear about a problem.

## Related

- [Offline maps and routing](./offline-maps-and-routing)
- [Turn-by-turn navigation](./navigation)
- [Recording a ride](./recording-a-ride)
- [Sensors and your watch](./sensors-and-watch)
- [Import and export](./import-and-export)
- [Getting started](./getting-started)
