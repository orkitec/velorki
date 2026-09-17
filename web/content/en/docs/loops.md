---
title: Loops
description: Ask Velorki for a round trip of a given distance that ends where it started, then step through the candidates until one looks right.
order: 3
---

A loop is a ride that comes back to where it started, and Velorki generates them from a distance rather than from points you tap. Use the **Loop** button when you know how far you want to ride but not where, and use it to close a route you have already drawn.

The loop generator is a plain algorithm running on your phone. It is free, it needs no server beyond the routing itself, and no model is involved.

## Open it

Tap **Loop** in the toolbar of the route sheet on the **Plan** tab. The sheet is titled **Make a loop**, and what it offers depends on what the planner already holds.

## Close a route you have drawn

If the planner already has two or more points, the sheet offers to bring the route back to its start.

1. It says "Ride back to where you started."
2. Under **BIKE**, pick the profile. It is the same setting as the chips on the planner, so changing it here changes it there.
3. **Different way back** is on by default, with the note "Avoids the roads you already rode." Switch it off and the return leg may reuse the way out.
4. Tap **Close the loop**. Velorki appends a copy of your first point, routes the way home, and shows the result as `48.2 km · 720 m up`.
5. **Another way back** keeps the outward leg exactly as it is and asks only for a different return. Press it as often as you like; each press is one undo step. It is greyed out while **Different way back** is off.
6. **Done** closes the sheet. The loop is on the planner map as an ordinary route you can edit and save.

## Make a loop from scratch

If the planner is empty, or holds a single point, the sheet asks for a distance instead.

1. **Where it starts.** With a point already on the map, that point is the start. Otherwise the line reads **From your position**, and Velorki asks for location the first time. If no fix can be had it falls back to the map centre and the line changes to **From the map centre**.
2. **DISTANCE.** Drag the slider. Metric runs from 5 to 200 km in 5 km steps, imperial from 3 to 125 miles in 1 mile steps, and the chosen figure is shown large above it. It opens at whatever you asked for last, 30 km the first time.
3. **BIKE.** The same five profiles as the planner.
4. **Different way back.** On means a real circle; off means riding out to a far point and back the same way.
5. Tap **Make a loop**.

## While it searches

Velorki sends the request out in eight directions and gives itself 25 seconds. A progress bar counts the finished requests, and **Stop** on the right ends the search early while keeping whatever has already been found.

## Choosing among the candidates

You are not given a list to read. Every candidate is scored on how close it comes to the distance you asked for, how much climbing it has per kilometre, how much of it is unpaved, how much runs on cycleways and bike networks, how much of it repeats the same roads, and how much is on main roads. The best one is handed straight to the planner and drawn on the map, and the sheet shows only its summary line, `48.2 km · 720 m up`.

To see the next one down, tap **Another**. That walks one step down the ranking with no new routing at all, so it is instant. When the ranking runs out, Velorki searches again with the eight directions rotated half a step, so the new attempts land between the old ones.

Every candidate you look at is a real route on the planner: pan around it, drag a point, read its elevation profile, and **Save** it when one is right.

If the slider or the bike profile changes after a search, the result is stale and the button goes back to **Make a loop**.

## Asking for a loop past a particular place

The loop sheet has no field for a place to ride past, and no hill or surface preference. Those come from the [assistant](./assistant): a sentence like "A gravel loop of about 80 km with a café stop" or "a hilly 60 km loop from here past the lake" becomes a request with a via point and preferences attached, and the loop generator does the work. The assistant is part of Velorki Plus; the loop sheet itself is free.

## When it finds nothing

- **"No loop found here, try another distance."** Some places, an island or a dead-end valley, simply have no road network for a circle of that length. Move the distance up or down by a good margin, or start somewhere else.
- **"Turn on location or tap the map to set a start."** No start point could be worked out. Allow location, or tap the map first.
- **"Loop search failed:"** with a reason means the routing itself failed. Check [troubleshooting](./troubleshooting).

Closing the sheet cancels a running search but keeps what it had already found.

## Related

- [Planning a route](./planning-a-route)
- [Assistant](./assistant)
- [Offline maps and routing](./offline-maps-and-routing)
- [Library](./library)
