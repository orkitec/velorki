---
title: Turn-by-turn navigation
description: Follow a route while you record, with a turn banner and spoken cues, and see what Velorki does when you leave the route.
order: 6
---

Velorki guides you along a route while a ride is recording: a banner over the map shows the next turn, and a voice says it out loud. Turn on the three navigation switches, pick a route to follow on the Record tab, and start the ride.

Navigation is free, works offline where you have downloaded the routing data, and needs no account.

## Turn it on

The three switches live in two places at once, and they are the same setting either way: in **Settings → Navigation**, and on the Record tab's sheet below **Keep screen on**.

1. **Turn directions**, "Show the next turn while you record along a route". This is the master switch; the other two are greyed out while it is off.
2. **Voice**, "Say the turns out loud".
3. **Re-route when off course**, "Plan a new way back onto the route when you leave it".

Then on the **Record** tab pick something under **Follow a route**: **The route on the Plan tab** if the planner holds a route, or any route from your library. Start the ride and the banner appears.

## The turn banner

A pill across the top of the map, over the map controls. Left to right: an arrow for the turn, the distance to it in big figures, and the instruction.

The instructions are: **Turn left**, **Turn right**, **Bear left**, **Bear right**, **Turn sharp left**, **Turn sharp right**, **Keep left**, **Keep right**, **Turn around**, **At the roundabout, take exit 3**, **Take the exit on the left**, **Take the exit on the right**, **Continue** and **Arrive**.

When a second turn follows close behind the first, a small grey arrow for it sits at the end of the pill.

A route imported with a cue sheet shows the author's own words for a turn instead, "Turn left onto Main Street", and the voice says them too.

A point of interest on the route, a water fountain or a dismount zone from an imported file, takes the banner when it is nearer than the next turn and within 300 m: its icon, the distance and its name, a hazard as "Caution: …" in the warning colour. The voice announces it once, with the same lead a turn gets, "In 100 metres, caution: start dismount zone". See [sensors and your watch](./sensors-and-watch) for what reaches the watch, and [import and export](./import-and-export) for where the points come from.

At the end of the route the banner turns green and says **You have arrived**.

## The voice

With **Voice** on, each turn is announced once as you approach it and once more at the turn: "In 200 metres, turn left", then "Now turn left". Two turns close together are spoken as one cue, "turn left, then turn right". Imperial units get "In 500 feet", "In a quarter mile", "In half a mile", "In one mile".

**Announce turns** in Settings → Navigation sets how early: the slider is in seconds, and the hint reads "12 seconds before the turn at your speed, never closer than 50 metres". Because it counts seconds rather than metres, the cue comes at the same moment whether you are crawling up a hill or flying down one.

The banner also carries a **mute** button while Voice is on. It silences the voice **for the rest of this ride only** and does not touch your setting; the next ride starts unmuted.

## Choosing a voice

1. **Settings → Navigation → Speaking voice**.
2. The first row is **System default**, "The phone's own voice for your language". Below it is every voice the phone has installed, named like "Female voice 2 (United Kingdom)".
3. Tap a row to choose it. It speaks a sample as you do.
4. Tap **Try** on any row to hear it without choosing it.

Two things worth knowing:

- **Voices that need the internet.** Some phones offer voices that are generated on a server. They are hidden until you turn on **Show online voices** at the bottom, and each is marked **Needs internet**. Velorki warns: "A voice marked with a cloud is generated online. Where there is no signal, the turn goes unspoken or comes late. For rides, prefer a voice stored on the phone."
- **On an iPhone with only the compact voice**, Velorki shows **Better voices are a download away** and walks you through it: Settings → Accessibility → Spoken Content → Voices → your language → tap the cloud next to an Enhanced or Premium voice. Afterwards the app picks the best voice on the phone by itself.

If the phone has no voice for your language at all: "No voice for your language is installed. Add one in the phone's settings, under text-to-speech or Spoken Content."

## When you leave the route

Most wrong turns are undone within a block, so Velorki does not re-plan the moment you stray. It works through three stages instead, and each one costs more than the last.

### 1. Guide you back

Roughly **75 metres** off the route, for two fixes running or about eight seconds, and the banner turns orange: **Back to the route, on your left**, with the distance to the nearest point of the route still ahead of you. Nothing is re-routed; the plan stays exactly as it was, and the moment you rejoin it the ordinary turns carry on.

**Tap the banner** to skip the wait and ask for a detour now.

### 2. Compute a detour

Still off the route about **half a minute later, or 150 metres from where you left it** (and never sooner than 15 seconds, so a burst of bad fixes costs nothing), and Velorki routes you back. It tries three places to rejoin the plan, 300 metres, 800 metres and 2 kilometres further along it, counted from where you have got to beside the plan rather than where you left it, and takes the first that is not a silly diversion and does not send you the wrong way down a one-way street, along a pavement or back the way you came. The answer is drawn as a branch beside your original plan and stitched to the rest of it, so the turns after the rejoin are the ones you already had.

The aim is the nearest sensible way back onto the plan, not the fastest way to the finish. While you are off route the branch is recomputed when you have drifted another 50 metres or so, and at most every 20 seconds, unless you are already making your own way back. Ride away from two branches and Velorki takes the hint: it plans once from where you are to the destination and then leaves you in peace until you have followed that route for a while, rejoined it, or asked. Get back within about 30 metres of the plan and the branch disappears without a word.

The banner says **Recalculating…** while it works, and **Route recalculated** when it lands.

### 3. Start again from here

**New route from here** is a button beside the banner while you are off route. It abandons the rest of the plan and routes from where you stand to the destination. Velorki also does this by itself if you are more than 3 kilometres off the route for more than five minutes, which is what a deliberate change of plan looks like.

All of the distances above grow with how bad your GPS fix is, roughly doubling with the reported accuracy, so a phone under trees does not keep declaring you lost. They stop growing at 100 metres of accuracy, so a phone that has lost the sky entirely cannot switch off-route detection off.

With **Re-route when off course** switched off, stage 1 still happens and stages 2 and 3 do not: you get the banner pointing back at the route and nothing more.

## The map while navigating

- The compass button on the map swaps between **North up** and **Map turns with you**. Your choice is remembered for the next ride.
- **Show my position** picks the following up again after you have panned the map.
- While you are on the route the position marker is drawn on the route and pointed along it, rather than wandering with the fix.

## Related

- [Recording a ride](./recording-a-ride)
- [Planning a route](./planning-a-route)
- [Offline maps and routing](./offline-maps-and-routing)
- [Settings and appearance](./settings-and-appearance)
- [Troubleshooting](./troubleshooting)
