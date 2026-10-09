---
title: Stops on the map
description: Show water, cafés, toilets, bike repair and other stops on the map, in the area you look at or along the route ahead, and switch on the cycle map.
order: 5
---

Velorki can draw the places a ride stops at on the map: drinking water, cafés, bakeries, toilets, bike repair stations and more. They come from the place index of the routing data on the phone, so they need the area downloaded (see [offline maps and routing](./offline-maps-and-routing)), work with no signal and send nothing anywhere.

## The Layers button

**Layers** sits in the button column on the right of the map, on the Plan and the Record tab. Its sheet holds:

- **Cycle map**: "Bike lanes, paths and cycle routes from your downloaded areas · works offline · shown when zoomed in". Drawn by the app from the routing data on the phone, so it needs no connection, and only where an area is downloaded. Its parts unfold below the switch, see [the cycle map](#the-cycle-map).
- **Online cycle map**: "CyclOSM's map with bike shops and parking · needs a connection". CyclOSM's overlay, fetched online. The two cycle maps take turns: turning one on turns the other off.
- **Stops**, a switch, off until you turn it on. Under it, the kinds to show, by group: **Cycling stops**, **Overnight** and **Landmarks**. Tap a kind to show or hide it. The first time, drinking water, cafés, bakeries, toilets and bike repair stations are picked. With the switch off the kinds fold away; your pick is kept for the next time.

The button is highlighted while the cycle map, the online cycle map or the stops are on.

## The cycle map

From zoom 13 on, the cycle map draws what the routing data knows about riding a bike. With it on, a chip per part unfolds below the switch, each with a sample of its line as legend. Tap a chip to show or hide the part; the choice is kept.

| Part | Drawn as |
| --- | --- |
| **Bike lanes & tracks** | Cycleways solid blue, cycle streets with a pale band; tracks solid and lanes dashed, beside the road on their side when zoomed in |
| **Shared paths** | Paths shared with walkers dashed teal, footways bikes may use dotted grey-blue |
| **Two-way for bikes** | Arrows on one-way streets that bikes may ride both ways, from zoom 15 |
| **National routes**, **Regional routes**, **Local routes** | Signed cycle routes as a violet halo, stronger the farther the route reaches |
| **Unpaved & bumpy** | Unpaved ways an ochre dash, bumpy ways red ticks |
| **Barriers** | Gates, bollards and stiles as dots from zoom 15; red where the bike has to be carried |

All parts are on at first except **Unpaved & bumpy** and **Barriers**.

On the Plan tab, with the cycle map on over an area that is not downloaded, a chip says **No cycle map here — area not downloaded**, with **Download**; a tap opens the download for the visible area. If the stops chip applies too, it comes first.

## In the area you look at

With **Stops** on, the stops in the part of the map you can see appear from zoom 11 on. Zoomed out, close stops are gathered into bubbles with a count; from zoom 15 they split into single stops with their icons. Tap a bubble to zoom in to where it splits.

Zoomed out further than that, a chip says **Zoom in to see stops**; tap it and the map zooms in to where they show.

Where the area is not downloaded, the chip instead says **No stops here — area not downloaded**, with **Download**; a tap opens the download for the visible area.

## Along the route ahead

With a route chosen under **Follow a route** on the Record tab, the stops are the ones within 300 m of the route still ahead, up to 50 km, at any zoom. A line over the map lists the next of each kind with its distance along the route, "Drinking water · 2.4 km"; tap an entry to see the stop on the map. While the map follows you on a ride, it stays with you and the stop is only picked out.

Where none of the next 50 km of the route is downloaded, the same chip takes the place of that line.

**Along the route** and **In this area** in the Layers sheet switch between the two.

## Tap a stop

A stop opens its place card, the same card a search result opens: name, kind, town, how far from you and, with a route, how far off it. On the Plan tab it offers what to do with the place, **Route here**, **Start here**, **Add as a stop** or **Destination**; on the Record tab it only tells. **Details** and **Open in…** are on both. See [the place card](./search#the-place-card).

## Related

- [Search](./search)
- [Planning a route](./planning-a-route)
- [Turn-by-turn navigation](./navigation)
- [Offline maps and routing](./offline-maps-and-routing)
