---
title: Planning a route
description: Tap waypoints on the map, pick a bike profile, compare variants, read the elevation and surface stats, and save the route to your library.
order: 2
---

The Plan tab turns taps on the map into a bike route, computed on your phone wherever you have downloaded the routing data for. Use it whenever you want to decide a ride in advance, tweak it, and keep it.

## Set the start and the destination

1. Open the **Plan** tab and move the map to where you want to start.
2. **Tap the map** to set the start. The sheet at the bottom says "Tap the map again to add a destination."
3. **Tap again** for the next point. Every tap appends a point to the end of the route.
4. Velorki waits a moment after your last edit and then routes. While it works the sheet shows a spinner and **Routing…**; then the figures appear.

You can also start from a place instead of a tap. Type into the search field at the top, pick a result, and while the plan is still empty two buttons appear under the bike chips:

- **From my position** rides from where you are to the place you searched for.
- **Start here** makes the searched place the first point of the route.

Once a route is being planned, picking a search result simply adds that place as the next waypoint. See [search](./search) for what the search field can find.

## Add a point in the middle

**Long-press the map** to insert a point. Velorki works out which part of the drawn route your press was nearest to and inserts the new point into that stretch, so the route bends to go past it rather than doubling back at the end.

To move a point you already have, **drag its marker**. On a closed loop, dragging the start marker moves both ends so the loop stays closed.

## Change or remove a point

Tap a marker to open its menu. It is titled with the point's name, or **Point 2** if it has none, and offers:

- **Visit earlier** and **Visit later**, which swap the point with its neighbour in the order,
- **Remove point**,
- **Cancel**.

Each of those is one step on the undo stack.

## Pick the bike

The row of chips under the search field is the bike profile, and it decides which roads and paths the router likes:

| Profile | What it is for |
|---|---|
| **Touring** | the default: a sensible mix of quiet roads and cycle paths |
| **Road** | tarmac, fewer detours, avoids rough surfaces |
| **Gravel** | happy on tracks and unsealed surfaces |
| **MTB** | trails and singletrack |
| **Direct** | the shortest way, with the least regard for comfort |

Changing the profile re-routes the whole plan and clears any variants you had loaded.

## The toolbar

The row of buttons inside the route sheet:

- **Undo** takes back the last edit. There is no limit and no redo. Adding, inserting, moving, removing and reordering points, **Reverse**, **Clear**, closing a loop and taking another way back are all undoable; changing the bike profile, switching variant and loading a saved route are not.
- **Reverse** rides the route the other way round.
- **Clear** throws the plan away. That is undoable too.
- **Variants** asks for alternatives (see below).
- **Loop** opens the smart loop sheet, described in [loops](./loops).
- **Ask** opens the [assistant](./assistant). It is only there when the build talks to a Velorki server.

Under the row sits the full-width **Save** button.

## Variants

Velorki does not fetch alternatives on its own, because each one is a separate routing run. Tap **Variants** and it asks for up to four routes for the same points.

A chip row then appears above the toolbar: **Main**, **Alt 1**, **Alt 2**, **Alt 3**, each with a coloured dot matching its line on the map. Tapping a chip switches instantly, with no new computation, and draws that line on top.

Often fewer than four come back; whatever the router found is what you get. If none does, Velorki says "No alternatives available." Editing a waypoint or changing the bike profile clears the variants, so ask again afterwards.

## Read the route

The sheet header shows four figures: **Distance**, **Ascent**, **Descent** and **Est. time**. The estimated time comes from the typical speed of the chosen bike profile, not from a server, and it makes no allowance for your café stops.

Drag the sheet up for the rest.

### Elevation

The **Elevation** chart draws height against distance. Touch it and drag along it: a read-out appears next to the caption, in the form `12.3 km · 340 m`, and follows your finger. Lift it and the read-out goes. A route with no height data says "No elevation data for this route."

### Surface

The **Surface** bar is a single stacked bar of three shares that add up to the whole route, **Paved**, **Unpaved** and **Unknown**, with a legend of percentages underneath. Two more entries in the legend, **Cycleway** and **Busy roads**, overlap the first three rather than adding to them: they tell you how much of the route is on a dedicated cycleway, and how much is on a big road.

### Where it was routed

A small pill above the chart says **ON DEVICE** with a green dot when your phone computed the route from downloaded tiles, or **SERVER** when a routing server did. If the router did not say, the pill is not shown at all.

## Save it

1. Tap **Save**.
2. The **Save route** dialog offers a name, either the one it was saved under before or **Route 17 Sept 2026** with today's date.
3. Type your own name, or leave it, and tap **Save**.

You get "Route saved", and the route is in **Library → Routes**. Saving a route you had already saved updates that same entry instead of making a second one.

## When it will not route

- **"This route needs routing tiles that are not on this device."** appears in place of the figures when your phone has no routing data for the area and no routing server to fall back on. The button under it counts the tiles and their size, for example **Download 3 tiles (412 MB)**, and opens the offline screen with exactly those tiles picked out. See [offline maps and routing](./offline-maps-and-routing).
- **"No routing server configured, set one in Settings → Advanced."** is a card under the bike chips, and means this build has no server address at all.
- Anything else shows as **Routing failed:** with the reason.

## Related

- [Loops](./loops)
- [Search](./search)
- [Offline maps and routing](./offline-maps-and-routing)
- [Library](./library)
- [Turn-by-turn navigation](./navigation)
