---
title: Import and export
description: Open GPX and FIT files from anywhere on the phone, save them as routes or rides, and export yours to Komoot, Garmin or anything else.
order: 9
---

Velorki reads and writes GPX and FIT files, which is how routes and rides move between it and the rest of the world. All of it is free, needs no account and no connection, and works with Komoot, Garmin Connect, Strava, a bike computer or a plain file on the phone.

## Getting a file in

There are three ways, and all three end on the same import screen.

**Open with.** Tap a GPX or FIT file in your files app, in an email, or in the browser's downloads, and choose Velorki. On an iPhone that is "Open in Velorki" from Files, Mail or Safari.

**Share sheet.** In another app, share the file and pick Velorki. This is how a route arrives from Komoot or from a friend's message.

**The picker.** In the **Library** tab, tap **Import file** at the top right and choose the file yourself.

**A Ride with GPS link.** Share a route's link from the Ride with GPS app or a browser and pick Velorki, and the route lands on the import screen. A public route needs nothing else; a private one is fetched through your connected Ride with GPS account, and without one the screen says "This Ride with GPS route is private. Connect Ride with GPS in Settings to open it."

A file that cannot be imported opens the same screen with the reason: not a GPX or FIT file, unreadable, empty, or a link that could not be fetched.

Velorki works out what the file is by reading its first bytes, not by trusting its name or its type, so a `.gpx` that is really a FIT file still imports.

## The import screen

Titled **Import**, it shows:

- a map preview of the track, with the file's waypoints as small markers with their name: the points of interest a route came with, a dismount zone, a water fountain, a rough patch, in the colour of their kind,
- a **Name** field, pre-filled from the file name,
- the format and size, "GPX · 4,812 points",
- the time span, "16 Sept 2026, 09:12 – 16 Sept 2026, 13:40", or "The file carries no timestamps.",
- the distance, ascent, descent and duration, and the elevation profile,
- **SAVE AS**, a switch between **Route** and **Ride**.

The map stays at the top while the rest scrolls under it. When the file has turns or points of interest, a second page sits one swipe to the left, with two dots at the bottom saying which is up: the **CUE SHEET**, every turn and point of interest with its distance from the start, folded to eight lines with **Show all**. Tap a line and the map pans there at the zoom you have, pinned with its name; tap a marker on the map and the cue sheet comes up with its line selected and scrolled into view. A selected line opens with what there is to know, a hazard's note or the plain manoeuvre under the author's words.

A GPX route with a cue sheet, the route export of Ride with GPS or a Garmin course, brings its turns along: each cue becomes a turn instruction with the author's words, shown in the turn banner, on the cue sheet page and said by the voice. A GPX track carries no cue sheet; Velorki's own turn banner still works on it from the route's shape.

Velorki guesses **Route** or **Ride** from whether the points carry times: a recording does, a planned route does not. FIT courses carry a synthetic time base and are therefore guessed as a ride, so switch them over by hand. Nothing is written until you tap **Save**.

Afterwards you get "Alpine loop added to the library" or "Alpine loop added to your rides", and you land on the new item's page.

If the file will not open, Velorki says which problem it was: "That is not a GPX or FIT file.", "That file could not be read.", "That file has no track points." or "That file could not be opened."

## Getting a file out

**From a route** (Library → Routes → open it → **Export**):

| Format | Use it for |
|---|---|
| **GPX route** | a planned route for another planner, a phone app or a bike computer |
| **FIT course** | a Garmin, Wahoo or similar head unit that expects a course |

**From a ride** (Library → Rides → open it, or the ride page after finishing):

| Format | Use it for |
|---|---|
| **Export GPX track** | the recorded track with its timestamps |
| **Export FIT activity** | an activity file for a training platform |

Either way Velorki writes the file and hands it to the system share sheet, so you can put it in your files, mail it, or send it into another app.

## Komoot, Garmin and the rest

Velorki has no Komoot or Garmin integration, and does not need one: both speak GPX and FIT.

- **From Komoot to Velorki**: export the tour as GPX in Komoot, then share it to Velorki, or save it and open it with the **Import file** button.
- **From Velorki to Komoot**: export the route as **GPX route** and share it into Komoot's import.
- **To a Garmin head unit**: export the route as **FIT course**, or as **GPX route** if your device prefers that, and put it on the device the way you normally would, through Garmin Connect or by copying the file.
- **From a Garmin**: the `.fit` activity from the device imports as a ride.

Sending a route **to Strava** is also file-based, because Strava's API cannot create routes. See [Strava and Ride with GPS](./strava-and-ridewithgps).

## Related

- [Library](./library)
- [Strava and Ride with GPS](./strava-and-ridewithgps)
- [Sharing](./sharing)
- [Recording a ride](./recording-a-ride)
