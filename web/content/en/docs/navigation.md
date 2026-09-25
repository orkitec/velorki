---
title: Turn-by-turn navigation
description: Follow a route while you record, with a turn banner and spoken cues, and see what Velorki does when you leave the route.
order: 6
---

Velorki guides you along a route while a ride is recording: a banner over the map shows the next turn, and a voice says it out loud. Turn on the navigation switches, pick a route to follow on the Record tab, and start the ride.

Navigation is free, works offline where you have downloaded the routing data, and needs no account.

## Turn it on

The settings live in two places at once, and they are the same setting either way: in **Settings → Navigation**, and on the Record tab's sheet below **Keep screen on**.

1. **Turn directions**, "Show the next turn while you record along a route". This is the master switch; the rest is greyed out while it is off.
2. **Voice**, "Say the turns out loud".
3. **When you leave the route**: **Guide me back**, **New route to the destination** or **Don't re-route**. See [when you leave the route](#when-you-leave-the-route).

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

Most wrong turns are undone within a block, so nothing happens the moment you stray.

Roughly **75 metres** off the route, for two fixes running or about eight seconds, and the banner turns orange: **Back to the route, on your left**, with the distance to the nearest point of the route still ahead of you. That much happens in every mode, and costs no routing.

What happens next is the choice under **When you leave the route**. The wait is the same for both modes that route: about **three quarters of a minute off the route, or 150 metres from where you left it**, and never sooner than 15 seconds, so a burst of bad fixes costs nothing. **Tap the banner** to skip the wait.

### Guide me back

The default. Your plan is never replaced. Velorki works out a way back onto it, to a point **ahead** of you: it tries 300 metres, 800 metres and 2 kilometres further along the plan, counted from where you have got to beside it rather than where you left it, and takes the first that is not a silly diversion and does not send you the wrong way down a one-way street, along a pavement or back the way you came. The way back is drawn as its own line in its own colour, with the plan still on the map, and the banner and the voice follow it. Back on the plan, the way back disappears without a word and the plan's own turns carry on.

If you ride your own way instead, the way back is worked out again, but only once you are **300 metres** from where the last one was worked out, and never to a point short of the last one: it moves on with you rather than calling you back, and a minute of riding is the most it will ask of the router. It never gives up on the plan and plans a new route by itself.

### New route to the destination

When you leave the route, Velorki plans again from where you are to the destination, through the stops you have not reached yet, and that becomes the route for the rest of the ride. The old plan stays on the map, faint. Leave the new route too and it plans again, once you are 300 metres from where it last did, so it cannot go round in circles.

### Don't re-route

Only the orange banner, with the distance to the route and the direction back to it. Velorki asks the router for nothing, and tapping the banner does nothing.

### While you are off the route

The banner says **Recalculating…** while a way back or a new route is being worked out, and **Route recalculated** when a new route lands. **New route from here**, a button beside the orange banner, plans from where you stand to the destination straight away, whatever the setting.

All of the distances above grow with how bad your GPS fix is, roughly doubling with the reported accuracy, so a phone under trees does not keep declaring you lost. They stop growing at 100 metres of accuracy, so a phone that has lost the sky entirely cannot switch off-route detection off.

## The map while navigating

- The compass button on the map swaps between **North up** and **Map turns with you**. Your choice is remembered for the next ride.
- Your position sits in the part of the map above the sheet: in the middle of it with north up, low in it when the map turns with you, so most of what shows is the road ahead.
- The map keeps the zoom you pinch it to while it follows you, anywhere from a few kilometres across to a single block; only dragging it stops the following.
- **Show my position** picks the following up again after you have panned the map, at the usual street-level zoom.
- While you are on the route the position marker is drawn on the route and pointed along it, rather than wandering with the fix.
- The route's own points are on the map too: the start, the destination with its flag, every stop that has a name or a type, and the places beside the route. A point that only shapes the line is left out. The stops you have ridden past fade, and they stay faded if you go back. After a new route to the destination, the markers are still your route's.

## Related

- [Recording a ride](./recording-a-ride)
- [Planning a route](./planning-a-route)
- [Offline maps and routing](./offline-maps-and-routing)
- [Settings and appearance](./settings-and-appearance)
- [Troubleshooting](./troubleshooting)
