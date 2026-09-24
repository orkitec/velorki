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

## Mark a place beside the route

**Hold the map** where something worth remembering is, and the point sheet opens for a place there: a fountain, a station, a campsite. The route is not drawn through it. The marker wears the icon of whatever type you pick, with its name beside it, and a tap on it opens the sheet again.

To move a point you already have, **drag its marker**. On a closed loop, dragging the start marker moves both ends so the loop stays closed.

## On the route or beside it

Every point is one of two things, and the switch at the top of its sheet says which:

- **On the route**: a point the ride goes through. It wears a numbered disc, and the router bends the route to visit it.
- **Beside the route**: a place the ride passes. It wears its type's icon, and the route ignores it.

Flip a point to **Beside the route** and it leaves the route, which is drawn again without it; the marker stays where it is. Flip it to **On the route** and it becomes a point in the middle, at the place along the route where it lies, and the route is drawn again through it. Either way the name, the type and the note go with it.

## Change or remove a point

Tap a marker to open its sheet. From the top:

- **On the route** or **Beside the route**, the switch above,
- **Name**, with the type's icon in front of it, filled with the point's name or, for a point on the route with none, its number; a number left as it is names nothing. A place beside the route opens with an empty name,
- **Type**: a grid of tiles, four rows of four, all in view at once at any width: **Hazard**, **Water**, **Food**, **Other**, **Summit**, **Viewpoint**, **Shelter**, **Shop**, **Bike repair**, **First aid**, **Toilet**, **Campsite**, **Lodging**, **Parking**, **Transport** and **Turn**. **Lodging** is a bed rather than a pitch: a hotel, a hostel, a guesthouse. A **Turn** takes a **Direction** underneath (left, right, slight, sharp, keep left or right, straight, U-turn) and becomes a line of the route's cue sheet, so the turn banner and the voice say it there; a route imported with a cue sheet opens with its written turns as points of this type, ready to be changed. **Turn** is only offered for a point on the route: a cue of a road the ride does not take says nothing,
- **Note**,
- **Visit earlier** and **Visit later**, which swap the point with its neighbour in the order at once and leave the sheet open, so a point can be moved and named in one visit. Only for a point on the route; a place beside it has no place in the order,
- **Remove point**, for either kind,
- **Done**, which applies the switch, the name, the type and the note. Pull the sheet down to leave them as they were.

A swap, a removal, a flip and a Done that changed something are each one step on the undo stack. A named point on the route shows its name on its marker instead of its number, with its type's icon beside it. The details are saved with the route and come back when it is opened in the planner again; on a route opened from the library they go into the library at once, as long as the route has not been re-routed since, so there is no Save to press for a name or a note alone.

## What each point becomes in an exported file

Both kinds go out, and a head unit tells them apart as well as the format lets it:

- **GPX**: every place beside the route, and every point on the route with a name or a note, is written as a `<wpt>` with its type and its note. The points on the route are also the `<rtept>` list, so the file can be planned again.
- **FIT** and **TCX**: both kinds become course points on the course, beside the cue sheet's turns. FIT has a type of its own for water, food, a hazard, a summit, first aid, a toilet and a campsite; TCX only for water, food, a hazard, a summit and first aid. Lodging, parking and transport have no type in either, and go out as generic course points with their names. Anything else goes out as a generic course point with its name.
- A point that came out of a file keeps the word that file used for it. Export it again without changing its type and that word is written back, so a climb category, a sprint or a segment marker — things Velorki has no type of its own for — survives the round trip. Change the type and the new type's word is written instead.

## Pick the bike

The row of chips under the search field is the bike profile, and it decides which roads and paths the router likes:

| Profile | What it is for |
|---|---|
| **Touring** | the default: a sensible mix of quiet roads and cycle paths |
| **Road** | tarmac, fewer detours, avoids rough surfaces |
| **Gravel** | happy on tracks and unsealed surfaces |
| **MTB** | trails and singletrack |
| **Direct** | the shortest way, with the least regard for comfort |

Changing the profile re-routes the whole plan and clears any variants you had loaded. Velorki keeps the profile you chose last for the next start.

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

The sheet scrolls at any height; drag its handle or its title up for more room, or anywhere on it when there is nothing to scroll. Pulled all the way down, it folds into the navigation bar and leaves only the handle above the tabs, so the map is free; drag the handle up to bring it back.

### Elevation

The **Elevation** chart draws height against distance. Touch it and drag along it: a read-out appears next to the caption, in the form `12.3 km · 340 m`, and follows your finger. Lift it and the read-out goes. A route with no height data says "No elevation data for this route."

### Surface

The **Surface** bar is a single stacked bar of three shares that add up to the whole route, **Paved**, **Unpaved** and **Unknown**, with a legend of percentages underneath. Two more entries in the legend, **Cycleway** and **Busy roads**, overlap the first three rather than adding to them: they tell you how much of the route is on a dedicated cycleway, and how much is on a big road.

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
